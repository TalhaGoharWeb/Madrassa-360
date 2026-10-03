// POST /functions/v1/send-notification
//
// Server-side fan-out for the offline-first notifications framework
// (Phase 6 / Worker 2). The mobile/desktop client never sends push or
// email directly: it records the notification locally, then calls this
// function (via NotificationDispatcher → PushChannel/EmailChannel) when
// connectivity returns.
//
// Authorization: the caller must be authenticated AND either a platform
// admin (public.platform_admins) or an active member of the target tenant
// (public.tenant_memberships). Broadcasts — and messages addressed to OTHER
// users — additionally require the `notifications.send` effective permission
// or a legacy tenant_owner/tenant_admin rank (SEC-H4). A message to oneself
// stays membership-gated. Broadcasts are rate-limited (30/hour per tenant),
// targeted sends 120/hour per caller (SEC-H8).
//
// Body:
//   { tenant_id, notification_id, user_id?, type, title, title_urdu?,
//     body?, body_urdu?, data?, channels: ['push'|'email'] }
//   user_id null = tenant broadcast; otherwise a single recipient (who
//   must be a member of the tenant).
//
// Behavior per channel:
//   * The notification row is UPSERTED idempotently (ignoreDuplicates:
//     the same client UUID retried after a timeout never duplicates).
//   * Per-user channel opt-outs (public.notification_preferences) are
//     respected before fan-out.
//   * push: tokens from public.notification_device_tokens. Requires the
//     FCM_SERVICE_ACCOUNT_JSON function secret; without it returns
//     status 'no_fcm_configured' (the client maps this to `skipped`, not
//     a retryable failure).
//   * email: recipient addresses resolved via the Auth admin API.
//     Requires the RESEND_API_KEY function secret; without it returns
//     status 'email_unconfigured' (client maps to `skipped`).
//
// Secrets come ONLY from env (supabase secrets set). No credentials are
// ever accepted from the client body or hardcoded.
//
// Success: 200 { notification_id, channels: { push: {...}, email: {...} } }
//   each channel result: { sent: bool, status: string, delivered?: number,
//                          total?: number, detail?: string }

import {
  badBodyResponse,
  hasEffectivePermission,
  invalidBodyResponse,
  json,
  logServerError,
  newCorrelationId,
  preflight,
  rateLimit,
  readJsonBody,
  resolveJwtUser,
  serviceClient,
  tooManyRequests,
  validateBody,
  type FieldRule,
} from "../_shared/guard.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.44.4";

const ALLOWED_CHANNELS = new Set(["push", "email"]);

interface ChannelResult {
  sent: boolean;
  status: string;
  delivered?: number;
  total?: number;
  detail?: string;
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

function b64url(input: string): string {
  return btoa(input).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): Uint8Array {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

/** Mint a Google OAuth2 access token for FCM HTTP v1 (service account). */
async function fcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const unsigned =
    `${b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.` +
    b64url(
      JSON.stringify({
        iss: sa.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      }),
    );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(sa.private_key).buffer as ArrayBuffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
  const form = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion: `${unsigned}.${sigB64}`,
  });
  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });
  if (!resp.ok) {
    throw new Error(`oauth_token_failed: ${resp.status}`);
  }
  const body = (await resp.json()) as { access_token?: string };
  if (!body.access_token) throw new Error("oauth_token_failed: no_token");
  return body.access_token;
}

function escHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

Deno.serve(async (req: Request): Promise<Response> => {
  const pf = preflight(req);
  if (pf) return pf;
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  let supabase: SupabaseClient;
  try {
    supabase = serviceClient();
  } catch {
    return json(
      {
        error: "server_misconfigured",
        message: "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are not set.",
      },
      500,
    );
  }

  // ── authenticate caller ──────────────────────────────────────
  const callerOr = await resolveJwtUser(req, supabase);
  if (!callerOr.ok) return callerOr.response;
  const callerId = callerOr.userId;

  // ── validate body ────────────────────────────────────────────
  const parsed = await readJsonBody(req);
  if (!parsed.ok) return badBodyResponse(parsed);
  const body = parsed.body;

  // SEC-M12: per-field allow-list + length caps. Unknown keys → 400.
  const BODY_SCHEMA: Record<string, FieldRule> = {
    tenant_id: { required: true, type: "uuid" },
    notification_id: { required: true, type: "uuid" },
    user_id: { type: "uuid", allowNull: true },
    type: { required: true, type: "string", minLength: 1, maxLength: 64 },
    title: { required: true, type: "string", minLength: 1, maxLength: 200 },
    title_urdu: { type: "string", maxLength: 200 },
    body: { type: "string", maxLength: 2000 },
    body_urdu: { type: "string", maxLength: 2000 },
    data: { type: "object", maxBytes: 3072 },
    channels: { required: true, type: "array", minItems: 1, maxItems: 4 },
  };
  const valid = validateBody(body, BODY_SCHEMA);
  if (!valid.ok) return invalidBodyResponse(valid.problems);

  const tenantId = body["tenant_id"] as string;
  const notificationId = body["notification_id"] as string;
  const targetUserId = (body["user_id"] as string | null | undefined) ?? null;
  const type = body["type"] as string;
  const title = body["title"] as string;
  const titleUrdu = (body["title_urdu"] as string | undefined) ?? null;
  const notifBody = (body["body"] as string | undefined) ?? null;
  const bodyUrdu = (body["body_urdu"] as string | undefined) ?? null;
  const data = (body["data"] as Record<string, unknown> | undefined) ?? {};
  const channels = body["channels"] as string[];

  if (!channels.every((c) => ALLOWED_CHANNELS.has(c))) {
    return json(
      { error: "bad_request", message: "channels must be a subset of ['push','email']." },
      400,
    );
  }
  const dataKeys = Object.keys(data);
  if (
    dataKeys.length > 20 ||
    !dataKeys.every((k) => /^[a-zA-Z0-9_.-]{1,64}$/.test(k))
  ) {
    return json(
      { error: "bad_request", message: "data: too many keys or invalid key format." },
      400,
    );
  }
  const wanted = [...new Set(channels)];

  // ── authorize ────────────────────────────────────────────────
  // Platform admins pass. Otherwise the caller must be an active member
  // of the tenant. Broadcasts — and messages to OTHER users —
  // additionally require the `notifications.send` effective permission or
  // a legacy owner/admin rank (SEC-H4): plain membership must not buy a
  // tenant-wide phishing cannon. A message to ONESELF stays
  // membership-gated.
  const { data: adminRow } = await supabase
    .from("platform_admins")
    .select("user_id")
    .eq("user_id", callerId)
    .maybeSingle();

  let callerRole: string | null = null;
  if (!adminRow) {
    const { data: membership, error: mErr } = await supabase
      .from("tenant_memberships")
      .select("user_id, role")
      .eq("tenant_id", tenantId)
      .eq("user_id", callerId)
      .eq("is_active", true)
      .maybeSingle();
    if (mErr || !membership) {
      return json(
        { error: "forbidden", message: "Not a member of this tenant." },
        403,
      );
    }
    callerRole = membership.role as string;
  }

  const isBroadcast = targetUserId === null;
  const isSelfTarget = targetUserId !== null && targetUserId === callerId;
  if (!adminRow && (isBroadcast || !isSelfTarget)) {
    const isLegacyManager =
      callerRole === "tenant_owner" || callerRole === "tenant_admin";
    const maySend = isLegacyManager ||
      await hasEffectivePermission(supabase, tenantId, callerId, "notifications.send");
    if (!maySend) {
      return json(
        {
          error: "forbidden",
          message: "Broadcasting notifications requires the notifications.send permission.",
        },
        403,
      );
    }
  }

  // ── rate limit (SEC-H8) ──────────────────────────────────────
  // Broadcasts are the expensive, abusable path: 30/hour per tenant.
  // Targeted sends: 120/hour per caller.
  if (isBroadcast) {
    const rl = await rateLimit(
      supabase,
      `send-notification:broadcast:${tenantId}`,
      30,
      3600,
    );
    if (!rl.allowed) return tooManyRequests(rl.retryAfterSec);
  } else {
    const rl = await rateLimit(
      supabase,
      `send-notification:targeted:${callerId}`,
      120,
      3600,
    );
    if (!rl.allowed) return tooManyRequests(rl.retryAfterSec);
  }

  // Targeted notifications may only address members of the same tenant
  // (prevents cross-tenant notification injection).
  if (targetUserId !== null) {
    const { data: target, error: tErr } = await supabase
      .from("tenant_memberships")
      .select("user_id")
      .eq("tenant_id", tenantId)
      .eq("user_id", targetUserId)
      .eq("is_active", true)
      .maybeSingle();
    if (tErr || !target) {
      return json(
        { error: "bad_request", message: "user_id is not a member of the tenant." },
        400,
      );
    }
  }

  // ── idempotent insert of the server notification row ──────────
  const { error: insErr } = await supabase.from("notifications").upsert(
    {
      id: notificationId,
      tenant_id: tenantId,
      user_id: targetUserId,
      type,
      title,
      title_urdu: titleUrdu,
      body: notifBody,
      body_urdu: bodyUrdu,
      data,
      channel: wanted[0],
    },
    { onConflict: "id", ignoreDuplicates: true },
  );
  if (insErr) {
    const cid = newCorrelationId();
    logServerError("send-notification", cid, "record_notification", insErr);
    return json(
      { error: "db_error", message: "Could not record notification.", ref: cid },
      500,
    );
  }

  // ── resolve recipients (target user or all active tenant members) ──
  let recipientIds: string[];
  if (targetUserId !== null) {
    recipientIds = [targetUserId as string];
  } else {
    const { data: members, error: memErr } = await supabase
      .from("tenant_memberships")
      .select("user_id")
      .eq("tenant_id", tenantId)
      .eq("is_active", true)
      .limit(2000);
    if (memErr) {
      return json({ error: "db_error", message: "Could not list members." }, 500);
    }
    recipientIds = (members ?? []).map((m) => m.user_id as string);
  }

  /** Recipient ids minus users who opted out of [channel]. */
  async function optedIn(channel: string): Promise<string[]> {
    if (recipientIds.length === 0) return [];
    const { data: prefs } = await supabase
      .from("notification_preferences")
      .select("user_id")
      .eq("tenant_id", tenantId)
      .eq("channel", channel)
      .eq("enabled", false)
      .in("user_id", recipientIds);
    const optedOut = new Set(
      (prefs ?? []).map((p: { user_id: string }) => p.user_id as string),
    );
    return recipientIds.filter((id) => !optedOut.has(id));
  }

  const results: Record<string, ChannelResult> = {};

  // ── push (FCM HTTP v1) ───────────────────────────────────────
  if (wanted.includes("push")) {
    const pushUsers = await optedIn("push");
    if (pushUsers.length === 0) {
      results["push"] = { sent: false, status: "no_recipients" };
    } else {
      const { data: tokens } = await supabase
        .from("notification_device_tokens")
        .select("token")
        .eq("tenant_id", tenantId)
        .in("user_id", pushUsers);
      const tokenList = [...new Set((tokens ?? []).map((t) => t.token as string))]
        .filter((t) => t.length > 0);
      if (tokenList.length === 0) {
        results["push"] = { sent: false, status: "no_recipients" };
      } else {
        const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
        if (!saRaw) {
          // Honest degradation: FCM not configured server-side. The
          // client maps this to `skipped`, never a retry loop.
          results["push"] = { sent: false, status: "no_fcm_configured" };
        } else {
          try {
            const sa = JSON.parse(saRaw) as ServiceAccount;
            if (!sa.project_id || !sa.client_email || !sa.private_key) {
              throw new Error("fcm_sa_malformed");
            }
            const accessToken = await fcmAccessToken(sa);
            const pushTitle = (titleUrdu ?? title) as string;
            const pushBody = (bodyUrdu ?? notifBody ?? "") as string;
            // FCM data values must be strings.
            const fcmData: Record<string, string> = {
              notification_id: notificationId as string,
              type: type as string,
            };
            for (const [k, v] of Object.entries(data)) {
              fcmData[k] = typeof v === "string" ? v : JSON.stringify(v);
            }
            let delivered = 0;
            for (const token of tokenList) {
              const resp = await fetch(
                `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
                {
                  method: "POST",
                  headers: {
                    Authorization: `Bearer ${accessToken}`,
                    "Content-Type": "application/json",
                  },
                  body: JSON.stringify({
                    message: {
                      token,
                      notification: { title: pushTitle, body: pushBody },
                      data: fcmData,
                    },
                  }),
                },
              );
              if (resp.ok) delivered++;
            }
            results["push"] = delivered > 0
              ? { sent: true, status: "sent", delivered, total: tokenList.length }
              : { sent: false, status: "fcm_send_failed", total: tokenList.length };
          } catch (e) {
            const cid = newCorrelationId();
            logServerError("send-notification", cid, "fcm", e);
            results["push"] = {
              sent: false,
              status: "fcm_error",
              detail: `ref:${cid}`,
            };
          }
        }
      }
    }
  }

  // ── email (Resend) ───────────────────────────────────────────
  if (wanted.includes("email")) {
    const emailUsers = await optedIn("email");
    const addresses: string[] = [];
    for (const uid of emailUsers.slice(0, 200)) {
      try {
        const { data: u } = await supabase.auth.admin.getUserById(uid);
        const email = u?.user?.email;
        if (email) addresses.push(email);
      } catch {
        // skip users we cannot resolve
      }
    }
    if (addresses.length === 0) {
      results["email"] = { sent: false, status: "no_recipients" };
    } else {
      const resendKey = Deno.env.get("RESEND_API_KEY");
      const from = Deno.env.get("RESEND_FROM_EMAIL") ?? "onboarding@resend.dev";
      if (!resendKey) {
        results["email"] = { sent: false, status: "email_unconfigured" };
      } else {
        const subject = (titleUrdu ?? title) as string;
        const textBody = (bodyUrdu ?? notifBody ?? "") as string;
        const html =
          `<div dir="rtl" lang="ur" style="font-family:sans-serif">` +
          `<h2>${escHtml(subject)}</h2><p>${escHtml(textBody)}</p></div>` +
          `<hr><p style="color:#888;font-size:12px">${escHtml(title as string)}` +
          (notifBody ? ` — ${escHtml(notifBody as string)}` : "") + `</p>`;
        try {
          const resp = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: {
              Authorization: `Bearer ${resendKey}`,
              "Content-Type": "application/json",
            },
            // RED-TEAM RT-02: recipients go in BCC — a broadcast must
            // never expose every parent's email address to every other
            // parent via the To header.
            body: JSON.stringify({
              from: `Madrassa 360 <${from}>`,
              to: from,
              bcc: addresses,
              subject,
              text: textBody,
              html,
            }),
          });
          results["email"] = resp.ok
            ? { sent: true, status: "sent", delivered: addresses.length, total: addresses.length }
            : { sent: false, status: "email_send_failed", detail: `resend_${resp.status}` };
        } catch (e) {
          const cid = newCorrelationId();
          logServerError("send-notification", cid, "email", e);
          results["email"] = {
            sent: false,
            status: "email_error",
            detail: `ref:${cid}`,
          };
        }
      }
    }
  }

  return json({ notification_id: notificationId, channels: results });
});
