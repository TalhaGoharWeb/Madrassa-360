# 🕌 مدرسہ 360 — Madrasa 360

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.47.4-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)
![CI](https://img.shields.io/badge/CI-passing-brightgreen?style=for-the-badge)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Windows-lightgrey?style=for-the-badge)

<p align="center">
  <b>اسلامی تعلیمی اداروں اور مدارس کے لیے مکمل، جدید اور اردو فرسٹ ERP نظام</b><br>
  <i>A complete, modern, Urdu-first ERP system for Islamic educational institutions and madrasas.</i>
</p>

</div>

---

## 📖 تعارف | Overview

**مدرسہ 360** مدارس، جامعات اور اسلامی اسکولوں کے مکمل انتظامی نظام کے لیے بنایا گیا ایک جدید ایپ ہے۔
یہ **Flutter** میں تیار کیا گیا ہے اور **Supabase** (PostgreSQL) اس کا بیک اینڈ ہے۔

- 🕌 مکمل **اردو** انٹرفیس — **جمیل نوری نستعلیق** فونٹ اور **دائیں سے بائیں (RTL)** لے آؤٹ
- 🏢 **ملٹی ٹیننٹ**: ایک ہی سسٹم میں متعدد مدارس/برانچز
- 🔐 **کردار پر مبنی رسائی (RBAC)** — سپر ایڈمن، ایڈمن، پرنسپل، استاد، والدین
- 📴 **آف لائن فرسٹ**: انٹرنیٹ کے بغیر حاضری/ڈیٹا محفوظ، بعد میں خودکار سنک
- 📊 حاضری، فیس، امتحانات، لائبریری، ہاسٹل اور رپورٹس — سب ایک جگہ

**Madrasa 360** is a modern management app for madrasas and Islamic schools, built with
**Flutter** and powered by **Supabase** (PostgreSQL). It offers a fully Urdu interface with
Jameel Noori Nastaleeq typography, complete RTL layout, multi-tenant support, role-based
access control, an offline-first sync engine, and modules for attendance, fees, exams,
library, hostel and reports.

---

## ✨ اہم خصوصیات | Key Features

### 🏢 ملٹی ٹیننٹ انتظام | Multi-Tenant Management
- ایک ہی انسٹالیشن میں متعدد مدارس/برانچز چلائیں
- ہر ادارے کا ڈیٹا مکمل الگ (Row Level Security کے ذریعے)
- ٹیننٹ آن بورڈنگ اور لائسنسنگ

### 👨‍🎓 طلبہ و اساتذہ | Students & Staff
- داخلے، مکمل بائیو ڈیٹا، سرپرست کی معلومات، درجہ/کلاس الاٹمنٹ
- اساتذہ کی ڈائریکٹری، مضامین کی تفویض، عہدے اور رابطے

### 📝 حاضری | Attendance
- روزانہ اور پیریڈ وائز حاضری: حاضر، غیر حاضر، رخصت، دیر سے
- آف لائن حاضری محفوظ، انٹرنیٹ آتے ہی خودکار سنک

### 💰 فیس و مالیات | Fees & Finance
- ماہانہ فیس واؤچر، ادائیگی کی وصولی اور رسیدیں
- آمدنی/اخراجات کا کھاتہ، تنخواہوں کا ریکارڈ

### 📚 امتحانات و نتائج | Exams & Results
- نمبرات کا اندراج، GPA، رپورٹ کارڈ اور پرنٹ ایبل رپورٹس (PDF/Excel)

### 📖 لائبریری (مکتبہ) | Library
- کتب کا اندراج، اجراء و واپسی کا ریکارڈ

### 🏠 ہاسٹل | Hostel
- رہائشی طلبہ کا انتظام

### 📢 اطلاعات و نوٹیفکیشن | Announcements & Notifications
- انتظامی اعلانات، والدین کو براہ راست پیغامات، پش نوٹیفکیشن

### 💾 بیک اپ | Backup
- مکمل ڈیٹا کا ایک فائل میں آف لائن بیک اپ اور بحالی

---

## 🖥️ ڈیش بورڈز | Role Dashboards

ہر ذمہ دار کو صرف اس کے کام کی سکرین دکھائی جاتی ہے:

| کردار | Role | ڈیش بورڈ |
|---|---|---|
| ماسٹر ایڈمن | Master Admin | تمام ٹیننٹس کا عالمی انتظام |
| سپر ایڈمن | Super Admin | ادارے کی مکمل نگرانی |
| پرنسپل | Principal | ادارے کی روزانہ کی صورتحال، رپورٹس |
| اکیڈمک ایڈمن | Academic Admin | درجات، نصاب، امتحانات |
| استاد | Teacher | اپنی کلاسز، حاضری، نمبرات |
| اکاؤنٹنٹ | Accountant | فیس وصولی، اخراجات |
| کلرک | Clerk | داخلے، ریکارڈ، دستاویزات |
| امتحانی انچارج | Exam Incharge | امتحانی انتظام اور نتائج |
| لائبریرین | Librarian | کتب کا اجراء و واپسی |
| ہاسٹل وارڈن | Hostel Warden | رہائشی طلبہ |
| والدین | Parent | اپنے بچوں کی حاضری، نتائج، فیس |

> ہر ڈیش بورڈ میں **"استعمال کا طریقہ"** کے عنوان سے اردو رہنمائی شامل ہے جو بتاتی ہے کہ اس سکرین کا ہر حصہ کیسے استعمال کریں۔
>
> Each dashboard includes an in-app Urdu **"How to use"** guide explaining every section of that screen.

---

## 🛠️ ٹیکنالوجی | Tech Stack

| حصہ | ٹیکنالوجی |
|---|---|
| ایپ فریم ورک | **Flutter 3.47.4** / Dart |
| اسٹیٹ مینجمنٹ | **Riverpod** (StateNotifier / AsyncNotifier) |
| بیک اینڈ | **Supabase** — PostgreSQL، Auth، Storage، Realtime |
| سرور لاجک | **Supabase Edge Functions** (Deno): `manage-tenant`، `manage-users`، `provision-tenant`، `export-tenant`، `send-notification` |
| آف لائن ڈیٹا بیس | **Drift** (SQLite) — آف لائن فرسٹ سنک انجن |
| رپورٹس | **pdf** / **printing** / **excel** — PDF اور XLSX ایکسپورٹ |
| پش نوٹیفکیشن | **Firebase Cloud Messaging** (Android/iOS/macOS) |
| فونٹس | **Jameel Noori Nastaleeq** (سرخیاں)، **Jameel Noori Kasheeda** (نمایاں عنوانات)، **Noto Naskh Arabic** (عام متن) |
| ماحولیاتی متغیرات | `flutter_dotenv` (`assets/.env`) |

### ڈیٹا بیس مائیگریشنز | Database Migrations

`supabase/migrations/` میں **22** مائیگریشنز ہیں (بنیادی اسکیما، ٹیننٹ سسٹم، RBAC، RLS،
اسٹوریج، فنانس، آڈٹ لاگز، نوٹیفکیشنز وغیرہ) — نئے سیٹ اپ پر یہ ترتیب سے لگائیں۔

There are **22 migrations** under `supabase/migrations/` (core schema, tenancy, RBAC,
RLS, storage, finance, audit logs, notifications, …). Apply them in order on a fresh project.

---

## 🚀 شروع کرنے کا طریقہ | Getting Started

### پیشگی شرائط | Prerequisites

- **Flutter SDK 3.47.4** (CI میں یہی ورژن پن ہے — اسی سے بلڈ کریں)
- ایک فعال [Supabase](https://supabase.com) اکاؤنٹ
- Windows بلڈ کے لیے: Windows 10/11 مشین یا GitHub Actions

> ⚠️ **اہم:** CI میں Flutter کا ورژن `3.47.4` پن ہے (`.github/workflows/*.yaml` میں
> `FLUTTER_VERSION`)۔ مقامی مشین پر بھی یہی ورژن استعمال کریں ورنہ Gradle/Kotlin
> ٹول چین کی غلطیاں آ سکتی ہیں۔

### مرحلہ 1: ریپو کلون کریں | Clone

```bash
git clone https://github.com/TalhaGoharWeb/Madrassa-360.git
cd Madrassa-360
```

### مرحلہ 2: ماحولیاتی متغیرات | Environment variables

```bash
cp assets/.env.example assets/.env
```

`assets/.env` میں اپنا Supabase ڈیٹا ڈالیں:

```env
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
```

> [!IMPORTANT]
> `assets/.env` کو کبھی Git میں کمیٹ نہ کریں — یہ `.gitignore` میں شامل ہے۔

### مرحلہ 3: ڈیٹا بیس سیٹ اپ | Database setup

1. [Supabase Dashboard](https://supabase.com/dashboard) میں اپنا پراجیکٹ کھولیں۔
2. **SQL Editor** میں `supabase/migrations/` کی فائلیں **ترتیب سے** چلائیں
   (`001_tenant_core.sql` سے `022_scope_failclosed.sql` تک)۔
3. پرانے طرز کی فائلیں (`supabase/01_schema.sql` … `06_rbac.sql`) نئے سیٹ اپ کے لیے
   ضروری نہیں — مائیگریشنز ہی اصل ذریعہ ہیں۔
4. **Edge Functions** ڈیپلائے کریں (`supabase/functions/`):
   `manage-tenant`، `manage-users`، `provision-tenant`، `export-tenant`، `send-notification`۔

### مرحلہ 4: ڈیپینڈنسیز اور رن | Install & run

```bash
flutter pub get
flutter run
```

### ٹیسٹ اور معیار | Tests & quality gates

```bash
flutter analyze        # اسٹیٹک تجزیہ — کوئی وارننگ قابل قبول نہیں
dart format --set-exit-if-changed lib test   # فارمیٹنگ (CI میں لازمی)
flutter test           # یونٹ/وِجٹ ٹیسٹ
```

---

## 📦 بلڈ بنانا | Building Releases

تمام ریلیز بلڈز **GitHub Actions** سے بنتے ہیں — `main` برانچ پر CI گرین ہونے کے بعد:

### 🪟 Windows انسٹالر

1. GitHub پر **Actions → Build Windows → Run workflow** دبائیں۔
2. کامیابی پر `windows-installer` آرٹیفیکٹ ڈاؤن لوڈ کریں (`Madrassa360-Setup-1.0.0.exe`)۔
3. ورژن `version.json` اور `pubspec.yaml` میں ایک ساتھ بڑھائیں (دونوں ایک جیسے ہوں)۔

### 🤖 Android APK

1. **Actions → Build Android → Run workflow** دبائیں۔
2. `build_type` منتخب کریں:
   - **`debug`** — ٹیسٹ کے لیے APK (ڈیبگ سائن شدہ، انسٹال ہو جاتا ہے؛ سائننگ سیکرٹس کی ضرورت نہیں)
   - **`release`** — پروڈکشن APK + AAB (دستخط شدہ؛ `ANDROID_KEYSTORE_BASE64`، `KEYSTORE_PASSWORD`، `KEY_ALIAS`، `KEY_PASSWORD` سیکرٹس درکار ہیں)
3. **ضروری سیکرٹس** (repo Settings → Secrets → Actions):
   `SUPABASE_URL` اور `SUPABASE_ANON_KEY` — ان کے بغیر APK میں بیک اینڈ کنفیگ نہیں ہوگی۔

> **نوٹ:** سائننگ سیکرٹس سیٹ نہ ہوں تو صرف **debug** APK بنائیں — یہ ٹیسٹنگ کے لیے
> مکمل انسٹال ایبل ہے، Play Store کے لیے نہیں۔

---

## 🧪 ڈیمو ڈیٹا | Demo Data

نئے سیٹ اپ کو فوری آزمانے کے لیے ڈیمو ڈیٹا پیک — ایک مکمل نمونہ مدرسہ
(**ڈیمو مدرسہ**): طلبہ، اساتذہ، درجات، حاضری، فیس اور امتحانی ڈیٹا۔
یہی لاگ اِن ویب ڈیش بورڈ اور Flutter ایپ **دونوں** میں کام کرتے ہیں (ایک ہی Supabase بیک اینڈ)۔

| فائل | مقصد |
|---|---|
| `demo/seed_demo_madrassa.sql` | ڈیمو ٹیننٹ + تمام ڈیٹا بناتا ہے (دوبارہ چلانا محفوظ) |
| `demo/remove_demo_data.sql` | ڈیمو ٹیننٹ اور اس کا تمام ڈیٹا حذف کرتا ہے |
| `demo/DEMO_README.md` | مکمل اردو/انگریزی رہنمائی |

**استعمال:**
1. پہلے تمام مائیگریشنز لگائیں۔
2. Supabase Dashboard → Authentication میں 5 ڈیمو صارفین بنائیں
   (`demo.admin@madrassa360.pk` وغیرہ — تفصیل `demo/DEMO_README.md` میں)۔
3. SQL Editor میں `demo/seed_demo_madrassa.sql` چلائیں۔
4. ڈیمو لاگ اِن سے ایپ/ڈیش بورڈ آزمائیں۔

**حذف کرنا:** `demo/remove_demo_data.sql` چلائیں — صرف ڈیمو ٹیننٹ کا ڈیٹا حذف ہوگا،
اصل ڈیٹا محفوظ رہے گا۔

A complete sample madrasa (**ڈیمو مدرسہ**) with students, teachers, classes,
attendance, fees and exam data. The same logins work in both the web dashboard
and the Flutter app (one shared Supabase backend). See `demo/DEMO_README.md`
for the full bilingual guide; removal is a single script
(`demo/remove_demo_data.sql`) scoped to the demo tenant only.

---

## 📁 پراجیکٹ کی ساخت | Project Structure

```
lib/
├── core/
│   ├── config/        # ایپ اور ٹیننٹ کنفیگریشن
│   ├── constants/     # رنگ، اجازتیں، ٹائپوگرافی (AppTypography)، سٹرنگز
│   ├── services/      # Supabase، Auth، نیٹ ورک، اسٹوریج، سنک انجن
│   ├── theme/         # اردو RTL تھیم، Material 3 ٹوکنز
│   ├── utils/         # تاریخ (عیسوی/ہجری)، ویلیڈیٹرز، ایرر ہینڈلنگ
│   └── widgets/       # مشترکہ بٹن، لوڈنگ، خالی اسٹیٹ وِجٹس
├── data/
│   ├── models/        # ڈیٹا ماڈلز (Student، Staff، Fee، Darja، Result…)
│   ├── repositories/  # Supabase PostgREST سے رابطہ
│   └── local/         # Drift (SQLite) آف لائن ڈیٹا بیس
├── presentation/
│   └── screens/
│       ├── auth/          # لاگ اِن، پاس ورڈ ریکوری
│       ├── dashboards/    # کردار کے مطابق ڈیش بورڈز (استاد، پرنسپل…)
│       ├── admin/         # ایڈمن/پرنسپل سکرینز
│       ├── teacher/       # حاضری، نمبرات
│       ├── parent/        # والدین کا پورٹل
│       ├── super_admin/   # ملٹی ٹیننٹ انتظام
│       ├── master_admin/  # پلیٹ فارم ایڈمن
│       ├── reports/       # رپورٹس اور ایکسپورٹ
│       ├── settings/      # ترتیبات، پروفائل
│       └── common/        # اعلانات، عمومی سکرینز
├── providers/             # Riverpod پرووائیڈرز
supabase/
├── migrations/            # 22 ڈیٹا بیس مائیگریشنز (001–022)
└── functions/             # 5 ایج فنکشنز (Deno)
assets/
├── fonts/                 # Jameel Noori + Noto Naskh فونٹس
└── images/                # ایپ آئیکن/لوگو
.github/workflows/         # CI، Build Windows، Build Android، Release
```

---

## 🗺️ روڈ میپ | Roadmap

- [x] ملٹی ٹیننٹ SaaS بنیاد، RBAC، RLS
- [x] حاضری، فیس، امتحانات، لائبریری، ہاسٹل
- [x] آف لائن فرسٹ سنک انجن اور بیک اپ/بحالی
- [x] اردو فرسٹ UI — نستعلیق ٹائپوگرافی، مکمل RTL
- [x] Windows انسٹالر اور Android APK (GitHub Actions)
- [x] ڈیمو ڈیٹا سیڈ پیک (`demo/seed_demo_madrassa.sql` + ہٹانے کی اسکرپٹ)
- [ ] ہر ڈیش بورڈ میں اردو "استعمال کا طریقہ" رہنمائی
- [ ] iOS اور Web بلڈز کی توثیق
- [ ] والدین کے لیے WhatsApp اطلاعات
- [ ] حافظہ ٹریکنگ فلو (سبق/سبقی/منزل)

---

## ⚖️ فونٹ لائسنس نوٹ | Font License Note

اس ایپ میں **Jameel Noori Nastaleeq** اور **Jameel Noori Kasheeda** فونٹس شامل ہیں۔
ان فونٹس کی **دوبارہ تقسیم (redistribution) کی لائسنسنگ کی تصدیق ابھی نہیں ہوئی** —
عوامی تقسیم سے پہلے لائسنس کی شرائط ضرور واضح کر لیں۔

The app bundles **Jameel Noori Nastaleeq** and **Jameel Noori Kasheeda** fonts.
**Redistribution licensing for these fonts is currently unverified** — please confirm
the license terms before any public distribution.

---

## 🤝 شراکت | Contributing

1. پراجیکٹ کو Fork کریں۔
2. فیچر برانچ بنائیں (`git checkout -b feature/AmazingFeature`)۔
3. کمیٹ کریں (`git commit -m 'Add some AmazingFeature'`)۔
4. پش کریں (`git push origin feature/AmazingFeature`)۔
5. Pull Request کھولیں۔

CI میں `flutter analyze`، `dart format` چیک، `flutter test` اور نو-موک-ڈیٹا گارڈ
لازمی پاس ہونا چاہیے۔

---

## 📄 لائسنس | License

**MIT License** کے تحت تقسیم شدہ — تفصیل کے لیے [`LICENSE`](LICENSE) دیکھیں۔

---

<div align="center">
  اسلامی تعلیمی اداروں کے لیے ❤️ کے ساتھ — <b>محمد طلحہ بن فرید</b><br>
  <i>Made with ❤️ for Islamic educational institutions — Muhammad Talha Bin Fareed.</i>
</div>
