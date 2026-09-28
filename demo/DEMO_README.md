# ڈیمو ڈیٹا پیک — Madrassa-360 Demo Data Pack

> **Review-only demo data.** This pack creates ONE demo tenant (`demo-madrassa` / **ڈیمو مدرسہ**)
> with a complete, realistic dataset so reviewers can explore every module.
> Everything is scoped to the demo tenant — removal is a single script.
>
> **یہ صرف جائزے (review) کے لیے ڈیمو ڈیٹا ہے۔** یہ پیک ایک ڈیمو مدرسہ بناتا ہے جس میں
> تمام ماڈیولز کا مکمل نمونہ ڈیٹا موجود ہے۔ حذف کرنے کے لیے صرف ایک اسکرپٹ چلائیں۔

---

## فائلیں / Files

| File | Purpose |
|---|---|
| `seed_demo_madrassa.sql` | Creates the demo tenant + all demo data (idempotent — safe to re-run) |
| `remove_demo_data.sql` | Deletes the demo tenant and ALL its data (no undo) |
| `DEMO_README.md` | This guide |

---

## مرحلہ ۰ — ڈیمو لاگ اِن بنائیں / STEP 0 — Create the demo logins

The SQL seed links data to **Supabase Auth users**, so create these 5 users **first**:

1. Supabase Dashboard → **Authentication → Users → Add user → Create new user**
2. Enter the email, set the password, and tick **"Auto Confirm User"**.
3. Repeat for all five. **Same password for everyone: `Demo@1234`**

> ⚠ یہ صارفین خود SQL سے نہیں بنتے — پہلے ڈیش بورڈ سے بنانا ضروری ہے۔
> The seed script cannot create Auth users; create them in the dashboard first.
> If a user is missing, the seed skips its linked rows with a NOTICE — just create
> the user and re-run the seed.

| Email | Role (کردار) | Password |
|---|---|---|
| `demo.admin@madrassa360.pk` | Admin / مالک (tenant owner) | `Demo@1234` |
| `demo.principal@madrassa360.pk` | Principal / پرنسپل | `Demo@1234` |
| `demo.teacher@madrassa360.pk` | Teacher / استاد | `Demo@1234` |
| `demo.accountant@madrassa360.pk` | Accountant / محاسب | `Demo@1234` |
| `demo.parent@madrassa360.pk` | Parent / والد | `Demo@1234` |

### 📱 ویب + ایپ ایک ہی بیک اینڈ / Web + app share one backend

Madrassa-360 کا ویب ڈیش بورڈ اور Flutter ایپ **ایک ہی Supabase backend** استعمال کرتے ہیں۔
یہ 5 لاگ اِن دونوں جگہ کام کریں گے — ڈیش بورڈ میں بھی، موبائل ایپ میں بھی۔

The web dashboard and the Flutter app use the **same Supabase backend**, so these
five logins work in **both** — no separate accounts needed.

---

## مرحلہ ۱ — سیڈ چلائیں / STEP 1 — Run the seed

1. Supabase Dashboard → **SQL Editor → New query**
2. Open `seed_demo_madrassa.sql`, paste the **entire file**, press **Run**.
3. The script ends with a verification table — expect:

| table | expected rows |
|---|---|
| tenants | 1 |
| darjas | 6 |
| classes | 8 |
| students | 28 |
| attendance | ~140 (5 days × 28 students) |
| invoices | 10 |
| payments | 7 |
| memberships | 5 |

> ✅ Idempotent: re-running never duplicates — every insert uses `ON CONFLICT DO NOTHING`
> with fixed UUIDs. دوبارہ چلانے سے ڈیٹا دہرانے (duplicate) نہیں ہوتا۔

> ⚠ **Do NOT run on a production database** holding real data unless you intend to
> add a demo tenant there. Live Supabase پر صرف ڈیمو/ٹیسٹ پراجیکٹ میں چلائیں۔

---

## ڈیمو ڈیٹا میں کیا ہے / What the demo contains

**Tenant:** ڈیمو مدرسہ — Demo Madrassa (`demo-madrassa`), لاہور • Urdu-first settings
(`Asia/Karachi`, `PKR`, Jameel Noori Nastaleeq receipts)

- **درجات (6):** ناظرہ قرآن، حفظ قرآن، درجہ اول تا چہارم
- **جماعتیں (8)** — 2 ناظرہ سیکشن ڈیمو استاد کے تحت
- **طلبہ (28)** — حقیقی اردو نام، والد کے نام، رول نمبر، فون، پتہ
- **عملہ (3):** کلرک، باورچی، چوکیدار (تنخواہوں سمیت)
- **حاضری:** پچھلے 5 تدریسی ایام (جمعہ چھٹی)، تمام طلبہ
- **فیس (legacy):** رواں ماہ — ناظرہ 500، حفظ 800، درجات 1000 روپے
- **امتحانات (2) + نتائج:** 4 مضامین فی طالب علم
- **اعلانات (4)** — داخلے، والدین میٹنگ، فیس کی آخری تاریخ، امتحانی شیڈول
- **مالیات (modern):** 4 کھاتے، 2 فیس اسٹرکچر، 6 فیس آئٹمز، 10 انوائسز،
  7 ادا شدہ ادائیگیاں (نقد/جاز کیش/ایزی پیسہ/بینک)، رعایت + اسکالرشپ،
  تنخواہ/بجلی اخراجات، عطیہ/زکٰوۃ آمدنی — سب posted، لیجر سمیت
- **روابط:** استاد↔جماعت تفویض، والد↔طلبہ سرپرستی
- **لائسنس:** Professional پلان، ایک سال کے لیے فعال
- **نوٹیفکیشنز (3)** + آڈٹ لاگ اندراجات

---

## مرحلہ ۲ — ڈیمو ڈیٹا حذف کریں / STEP 2 — Remove the demo data

Review finished? One script wipes the demo tenant completely:

1. Supabase Dashboard → **SQL Editor → New query**
2. Paste all of `remove_demo_data.sql` → **Run**.
3. Final check must show `remaining_demo_tenants = 0`.

> ⚠ **No undo.** حذف شدہ ڈیٹا واپس نہیں آئے گا۔
> The script deletes ONLY the `demo-madrassa` tenant's rows — other tenants are untouched.
> The 5 demo **Auth users are NOT deleted** by the script; remove them manually:
> Authentication → Users → select the `demo.*` users → Delete.

---

## Troubleshooting / مسائل کا حل

| Problem | Fix |
|---|---|
| `NOTICE: demo seed: auth user … not found — skipping` | Create that user in Authentication → Users (auto-confirm), then re-run the seed |
| Verification shows 0 students | The tenant insert failed — check the first error in the SQL editor output |
| Seed run twice shows same counts | Expected — the script is idempotent |
| `remaining_demo_tenants = 1` after removal | A delete failed — read the error; most likely a trigger was left disabled by an interrupted run; re-run the whole remove script |

---

*Branch: `demo/seed-data` • Review only — do not merge into main.*
