# 🕌 Madrasa 360 — Al Markaz al Islami Kasur

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-lightgrey?style=for-the-badge)

<p align="center">
  <b>المرکز الاسلامی قصور — اسلامی تعلیمی اداروں اور مدارس کے لیے مکمل اور جدید ERP نظام</b><br>
  <i>A unified, enterprise-grade Islamic educational ERP and administration system with native Urdu RTL support.</i>
</p>

</div>

---

## 📖 Overview

**Madrasa 360** (Al Markaz al Islami Kasur) is a modern management system crafted specifically for Islamic seminaries, madaris, and schools. Built with **Flutter** and powered by **Supabase**, it brings digitized administration to traditional institutions with native **Urdu Nastaleeq typography**, full **Right-to-Left (RTL)** layout, strict **Role-Based Access Control (RBAC)**, and multi-tenant capabilities.

---

## ✨ Core Features & Modules

### 🏢 1. Super Admin & Multi-Tenant Management
- Multi-madrasa management across different branches or organizations.
- Global system metrics, tenant onboarding, and institutional configuration.
- Global administrative privilege management.

### 🏛️ 2. Admin & Principal Portal
- **Student Admissions & Directory**: Complete biodata, guardian contacts, CNIC/B-Form, admission dates, and class allocation.
- **Staff & Asatizah Management**: Faculty directories, subject assignments, designations, and contact profiles.
- **Darjat (Classes) Management**: Hierarchical academic levels (Hifz, Nazra, Dars-e-Nizami, Tajweed, etc.) with section management.
- **User Account Management**: Admin can provision and manage logins for teachers, staff, and parents.

### 💰 3. Finance, Fees & Accounts
- **Fee Slip Generation**: Automated monthly fee vouchers with custom fee structures (tuition, boarding, books, transport).
- **Payment Collection & Receipts**: Real-time status tracking (Paid, Unpaid, Partial, Overdue).
- **Institutional Ledger**: Income and expense tracking, salary disbursement logs, and financial auditing.

### 👨‍🏫 4. Teacher Portal
- **Attendance Register**: Daily and period-wise attendance marking with instant visual statuses (حاضر, غیر حاضر, رخصت, دیر سے).
- **Examinations & Results**: Term exam score recording, subject grading, GPA calculation, and report generation.
- **Class Schedules**: Class timetables and syllabus milestone tracking.

### 👨‍👩‍👧 5. Parent & Guardian Portal
- **Child Progress Dashboard**: Live updates on daily attendance, exam performance, and teacher remarks.
- **Fee History & Vouchers**: View paid receipts, pending dues, and download fee slips.
- **Announcements**: Direct broadcast circulars from the administration.

### 📚 6. Library (Maktaba) Management
- Book inventory cataloging with Arabic/Urdu title indexing.
- Borrowing and return tracking with borrower logs and due dates.

---

## 🔐 Security & Role-Based Access Control (RBAC)

Madrasa 360 incorporates enterprise-grade security powered by **PostgreSQL Row Level Security (RLS)** in Supabase:

| Feature / Role | Super Admin | Admin | Teacher | Parent / Student |
| :--- | :---: | :---: | :---: | :---: |
| **Manage Multiple Madaris** | ✅ | ❌ | ❌ | ❌ |
| **Manage Staff & Admissions** | ✅ | ✅ | ❌ | ❌ |
| **Mark Class Attendance** | ✅ | ✅ | ✅ | ❌ |
| **Enter Examination Grades** | ✅ | ✅ | ✅ | ❌ |
| **Fee Collection & Finance** | ✅ | ✅ | ❌ | ❌ |
| **View Student Profile & Results** | ✅ | ✅ | ✅ (Assigned) | ✅ (Own Children) |
| **View Fee Vouchers** | ✅ | ✅ | ❌ | ✅ (Own Children) |
| **Maktaba (Library)** | ✅ | ✅ | ✅ (Issue/Return) | ✅ (Browse/Read) |

---

## 🛠️ Technology Stack & Architecture

- **Framework**: [Flutter](https://flutter.dev) (v3.5+)
- **Programming Language**: [Dart](https://dart.dev)
- **State Management**: [Riverpod](https://riverpod.dev) (`flutter_riverpod` with StateNotifier and AsyncNotifier)
- **Backend & Database**: [Supabase](https://supabase.com) (PostgreSQL, Supabase Auth, Storage & Realtime)
- **Environment Management**: `flutter_dotenv` for secure decoupled credential configuration
- **Typography & UI**: Custom Google Fonts and [Jameel Noori Nastaleeq](https://urdufonts.com) with bespoke Urdu RTL UI
- **Network & Connectivity**: `connectivity_plus` with offline awareness and resilient sync queues

### 🏛️ Architectural Blueprint
```
lib/
├── core/
│   ├── config/          # Madrasa & app-wide configuration
│   ├── constants/       # App colors, permissions, typography, strings
│   ├── services/        # Supabase, Auth, Network, Storage, Sync
│   ├── theme/           # Urdu RTL theme & Material Design 3 tokens
│   ├── utils/           # Date formatters (Gregorian & Hijri), validators, error handlers
│   └── widgets/         # Standard buttons, loading overlays, empty states
├── data/
│   ├── models/          # Data transfer models (Student, Staff, Fee, Darja, Result)
│   └── repositories/    # Abstracted data layer communicating with Supabase PostgREST
├── presentation/
│   ├── screens/
│   │   ├── admin/       # Principal & administrator screens
│   │   ├── auth/        # Login & password recovery
│   │   ├── common/      # Announcements, about, profile
│   │   ├── parent/      # Guardian dashboard & fee history
│   │   ├── super_admin/ # Multi-tenant branch administration
│   │   └── teacher/     # Class attendance & grading
│   └── widgets/         # Attendance tiles, drawer, navigation bars
└── providers/           # Riverpod state providers
```

---

## 🗄️ Database Migrations

The database structure is modularized into SQL migrations under the [`supabase/`](supabase/) directory:

1. [`01_schema.sql`](supabase/01_schema.sql) — Core tables: `madrasas`, `users`, `students`, `staff`, `darjat`, `attendance`, `fees`, `results`.
2. [`02_rls.sql`](supabase/02_rls.sql) — Granular Row Level Security policies enforcing data isolation per user role.
3. [`03_storage.sql`](supabase/03_storage.sql) — Storage bucket policies for student/staff profile pictures and documents.
4. [`04_seed.sql`](supabase/04_seed.sql) — Initial demonstration data for seeding local development environments.
5. [`05_new_modules.sql`](supabase/05_new_modules.sql) — Library (Maktaba) and institutional finance extensions.
6. [`06_rbac.sql`](supabase/06_rbac.sql) — Advanced Role-Based Access Control functions and triggers.

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.5.0 or later)
- [Dart SDK](https://dart.dev/get-dart)
- An active [Supabase](https://supabase.com) account

### Step 1: Clone the Repository
```bash
git clone https://github.com/TalhaGoharWeb/Madrassa-360.git
cd Madrassa-360
```

### Step 2: Configure Environment Variables
Copy the template configuration file:
```bash
cp assets/.env.example assets/.env
```

Open `assets/.env` and insert your Supabase credentials:
```env
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
```
> [!IMPORTANT]
> Never commit `assets/.env` to source control. It is explicitly ignored in [.gitignore](.gitignore) to prevent credential leakage.

### Step 3: Set Up Database in Supabase
1. Log in to the [Supabase Dashboard](https://supabase.com/dashboard).
2. Open the **SQL Editor** for your project.
3. Run the SQL files in order from the [`supabase/`](supabase/) folder:
   - `01_schema.sql`
   - `02_rls.sql`
   - `03_storage.sql`
   - `04_seed.sql` (Optional: for test data)
   - `05_new_modules.sql`
   - `06_rbac.sql`

### Step 4: Install Dependencies & Run
```bash
# Fetch Flutter packages
flutter pub get

# Run on an attached device or emulator
flutter run
```

---

## 📱 Supported Platforms

- 🤖 **Android**: Phones and Tablets (Android API 21+)
- 🍎 **iOS**: iPhone and iPad (iOS 13.0+)
- 💻 **Desktop**: Windows 10/11, macOS, and Linux
- 🌐 **Web**: Modern Evergreen Browsers (Chrome, Edge, Firefox, Safari)

---

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:
1. Fork the Project.
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`).
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the Branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

---

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for more details.

---

<div align="center">
  Made with ❤️ for Islamic Educational Institutions
</div>
