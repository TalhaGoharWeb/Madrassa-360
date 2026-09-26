# SMS / WhatsApp extension point

> Status: **documented extension point — no implementation exists.**
> There is deliberately no `SmsChannel` / `WhatsappChannel` class, no
> fake sender, and no stubbed HTTP call in this codebase. This document
> is the contract a future worker implements against.

## Why it is an extension, not a channel today

Sending SMS/WhatsApp needs a **paid third-party provider** (Twilio,
Vonage, a local Pakistani SMS gateway, or the WhatsApp Business Cloud
API) plus per-tenant sender identities. The project's free-first line
means no provider is chosen or configured now. The framework is built
so adding one later is mechanical and touches no existing channel.

## What already exists for the future channel

- **Channel ids reserved**: `NotificationChannelId.sms` / `.whatsapp`
  (`lib/core/notifications/notification_models.dart`).
- **Outbox**: `notification_outbox.channel` accepts any string; the
  dispatcher's claim/backoff/skip logic is channel-agnostic.
- **Triggers**: `NotificationTriggers._record` enqueues
  `NotificationChannelId.remote` — extend that list (or pass explicit
  channels) when the new channel lands.
- **Preferences**: `notification_preferences.channel` accepts any
  string; the UI renders `NotificationChannelId.implemented`, so add
  the new id there and the toggle UI appears with zero extra work.
- **Server**: `public.notifications.channel` has no CHECK constraint
  (017), so no migration is needed to record sms/whatsapp rows.
  `notification_device_tokens` is push-specific; SMS/WhatsApp need
  phone numbers — resolve them server-side from the tenant's
  parent/student contact records at fan-out time (no new table until a
  provider is chosen).
- **RLS**: unchanged — fan-out still goes through the
  `send-notification` Edge Function (service role).

## Interface to implement

```dart
class SmsChannel extends NotificationChannel {
  @override
  String get id => NotificationChannelId.sms; // or .whatsapp

  @override
  String get displayName => 'SMS';

  @override
  String get displayNameUrdu => 'ایس ایم ایس';

  /// SMS works on every platform (server-side send like email).
  /// WhatsApp likewise — the device never talks to the provider.
  @override
  bool supportsPlatform() => true;

  @override
  Future<ChannelDispatchResult> send(LocalNotificationRow notification) async {
    // 1. Invoke the send-notification Edge Function with
    //    channels: ['sms'] (extend its per-channel switch).
    // 2. Map the function result:
    //    sent:true            -> ChannelDispatchResult.sent()
    //    status 'unconfigured'/'no_recipients' -> .skipped(...)  (no retry)
    //    transport/provider 5xx                -> .failed(...)   (backoff)
  }

  @override
  Future<void> queue(AppDatabase db, LocalNotificationRow notification) =>
      NotificationOutboxStore.enqueue(
        db,
        tenantId: notification.tenantId,
        notificationId: notification.id,
        channel: id,
      );
}
```

Then register the instance in `notificationDispatcherProvider`'s
`channels:` list (`notification_providers.dart`) and add the id to
`NotificationChannelId.implemented` so the preferences UI picks it up.

## Server side (`supabase/functions/send-notification/index.ts`)

Add a `case 'sms':` / `case 'whatsapp':` to the per-channel fan-out:

1. Resolve recipients: broadcast → all tenant members with a verified
   phone (from the tenant's contact records); targeted → the
   notification's `user_id`.
2. Read provider credentials **only** from function secrets
   (e.g. `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`,
   `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`). Never hardcode,
   never accept them from the client body.
3. If the secrets are absent → return
   `{ sent: false, status: 'sms_unconfigured' }` (the client maps this
   to `skipped`, not `failed`).
4. Send via the provider's HTTPS API with the notification's
   `title_urdu`/`body_urdu` preferred for ur-PK recipients. Return
   `{ sent: true, provider_message_id }` on success.

## Cost guard (required before enabling)

SMS/WhatsApp are **per-message billed**. Before wiring a provider:

- put sends behind the existing per-channel preference toggle
  (default-on is wrong for a billed channel — consider default-off for
  sms/whatsapp, i.e. invert the default in `isEnabled` for those ids);
- add a per-tenant daily cap in the Edge Function (count today's
  `notifications` rows with `channel = 'sms'` for the tenant; refuse
  with `status: 'quota_exceeded'` past the cap);
- log every send with provider message id for billing reconciliation.

## Checklist for the implementing worker

- [ ] `SmsChannel`/`WhatsappChannel` implementing `NotificationChannel`
      (real provider call or honest `skipped('sms_unconfigured')` —
      never a fake "sent").
- [ ] Registered in `notificationDispatcherProvider`; id added to
      `NotificationChannelId.implemented`.
- [ ] Edge Function `case` with secrets-only credentials + graceful
      `unconfigured` degradation.
- [ ] Per-tenant daily cap + send logging.
- [ ] `017`-style migration ONLY if a new server table is truly needed
      (prefer resolving phone numbers from existing contact records).
- [ ] No real keys, tokens, or phone numbers committed anywhere.
