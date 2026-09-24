# Madrasa 360 — Supabase Backend Integration Plan

> **App:** Al Markaz al Islami Kasur — Madrasa 360  
> **Stack:** Flutter + Riverpod + Supabase  
> **Language:** Urdu (RTL)  
> **Roles:** Admin · Teacher · Parent  
> **Current state:** All data is local/mock; AuthService uses hard-coded credentials; no persistent storage.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Phase 0 — Prerequisites & Project Setup](#2-phase-0--prerequisites--project-setup)
3. [Phase 1 — Supabase Authentication](#3-phase-1--supabase-authentication)
4. [Phase 2 — Database Schema](#4-phase-2--database-schema)
5. [Phase 3 — Row Level Security (RLS) Policies](#5-phase-3--row-level-security-rls-policies)
6. [Phase 4 — Storage Buckets](#6-phase-4--storage-buckets)
7. [Phase 5 — Flutter Integration Layer](#7-phase-5--flutter-integration-layer)
8. [Phase 6 — Migrating Mock Data to Supabase](#8-phase-6--migrating-mock-data-to-supabase)
9. [Phase 7 — Realtime & Offline Support](#9-phase-7--realtime--offline-support)
10. [Phase 8 — Environment & Security Hardening](#10-phase-8--environment--security-hardening)
11. [Migration Checklist](#11-migration-checklist)
12. [File-by-File Change Summary](#12-file-by-file-change-summary)

---

## 1. Architecture Overview

### Current Architecture (Phase 1 — Mock)
```
LoginScreen
  └─ AuthService (hard-coded credentials, SharedPreferences session)
       └─ AuthProvider (Riverpod)

AttendanceScreen
  └─ MockStudents (in-memory list)
       └─ AttendanceProvider (Riverpod)
```

### Target Architecture (Supabase)
```
App Bootstrap (main.dart)
  └─ SupabaseService.init()
       └─ ProviderScope

LoginScreen
  └─ AuthRepository
       └─ Supabase Auth (email/phone + role-based custom claims)
            └─ AuthProvider (Riverpod StateNotifier)

Feature Screens (Attendance / Students / Fees / Results)
  └─ FeatureRepository  ← replaces Mock classes
       └─ Supabase PostgREST + Realtime
            └─ FeatureProvider (Riverpod AsyncNotifier)
```

The key principle: **Repository Pattern**. Every mock class gets a corresponding repository that talks to Supabase. Providers call repositories, never Supabase directly. This keeps the UI untouched.

---

## 2. Phase 0 — Prerequisites & Project Setup

### Step 0.1 — Create a Supabase Project

1. Go to [https://supabase.com/dashboard](https://supabase.com/dashboard) → "New project".
2. Name: `madrasa-360` | Region: choose Asia South (Mumbai) or closest.
3. Set a strong **database password** and save it in a password manager.
4. After creation, copy:
   - **Project URL** → `https://xxxxxxxxxxx.supabase.co`
   - **Anon (public) key** → starts with `eyJ...`
   - **Service role key** → for server-side migrations only; **never put this in the app**.

### Step 0.2 — Add Supabase Flutter Package

In `pubspec.yaml`, add the following dependencies:

```yaml
dependencies:
  # Supabase
  supabase_flutter: ^2.5.0       # Supabase client + auth + realtime
  
  # Already present (keep these)
  flutter_riverpod: ^2.4.9
  shared_preferences: ^2.2.2
  connectivity_plus: ^5.0.2
  intl: ^0.19.0
  google_fonts: ^6.1.0
  
  # New utilities needed
  flutter_dotenv: ^5.1.0         # Env variable management
  cached_network_image: ^3.3.1   # Student/staff photo caching
  image_picker: ^1.1.2           # Picking photos for upload
  uuid: ^4.4.0                   # Local UUID generation
```

Run: `flutter pub get`

### Step 0.3 — Create `.env` File

Create `assets/.env` (add to `.gitignore` immediately):

```env
SUPABASE_URL=https://ffhsrnkvjjedvclfwgmr.supabase.co
SUPABASE_ANON_KEY=***REDACTED-KEY-ROTATED-2026-09-25***
```
Service role key=***REDACTED-KEY-ROTATED-2026-09-25***


Add to `pubspec.yaml` assets:
```yaml
flutter:
  assets:
    - assets/
    - assets/.env        # ← add this line
```

Add `.env` to `.gitignore`:
```
assets/.env
```

---

## 3. Phase 1 — Supabase Authentication

### Step 1.1 — Enable Auth Providers in Supabase Dashboard

Go to **Authentication → Providers**:
- **Enable Email/Password** — primary method for admin & teachers.
- **Disable email confirmation** initially (re-enable in production).
- Set `Site URL` to your app's deep-link scheme: `madrasa360://`

### Step 1.2 — User Roles via Custom Claims (app_metadata)

Supabase uses JWT custom claims to store roles. After creating a user, set their role in `app_metadata`:

```sql
-- Run in Supabase SQL Editor after creating users
UPDATE auth.users
SET raw_app_meta_data = raw_app_meta_data || '{"role": "admin"}'
WHERE email = 'admin@madrassa360.pk';

UPDATE auth.users
SET raw_app_meta_data = raw_app_meta_data || '{"role": "teacher"}'
WHERE email = 'teacher@madrassa360.pk';

UPDATE auth.users
SET raw_app_meta_data = raw_app_meta_data || '{"role": "parent"}'
WHERE email = 'parent@amadrassa360.pk';
```

**Extract role in Flutter:**
```dart
final role = supabase.auth.currentUser?.appMetadata['role'] as String?;
```

### Step 1.3 — Create `lib/core/services/supabase_service.dart`

```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> init() async {
    await dotenv.load(fileName: 'assets/.env');
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,  // More secure for mobile
      ),
    );
  }
}
```

### Step 1.4 — Update `main.dart`

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize local storage
  await StorageService.init();
  
  // ← ADD THIS: Initialize Supabase
  await SupabaseService.init();
  
  SystemChrome.setPreferredOrientations([...]);
  runApp(const ProviderScope(child: Madrasa360App()));
}
```

### Step 1.5 — Create `lib/data/repositories/auth_repository.dart`

This is the **replacement for `AuthService`**. It wraps Supabase Auth:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/error_handler.dart';

enum UserRole { admin, teacher, parent }

class AppUser {
  final String id;
  final String email;
  final String name;
  final UserRole role;
  final String? phone;
  final String? photoUrl;

  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.phone,
    this.photoUrl,
  });

  factory AppUser.fromSupabase(User user, Map<String, dynamic> profile) {
    final roleStr = user.appMetadata['role'] as String? ?? 'teacher';
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      name: profile['name'] as String? ?? '',
      role: UserRole.values.firstWhere(
        (r) => r.name == roleStr,
        orElse: () => UserRole.teacher,
      ),
      phone: profile['phone'] as String?,
      photoUrl: profile['photo_url'] as String?,
    );
  }
}

class AuthRepository {
  final _client = SupabaseService.client;

  /// Sign in with email + password. Returns AppUser on success.
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) throw AuthenticationException('لاگ ان ناکام');

      // Fetch profile from public.profiles table
      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      return AppUser.fromSupabase(user, profile);
    } on AuthException catch (e) {
      throw AuthenticationException(_mapAuthError(e.message));
    }
  }

  /// Sign out current user
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Get currently logged-in user (from session)
  Future<AppUser?> getCurrentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final profile = await _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .single();
    return AppUser.fromSupabase(user, profile);
  }

  /// Auth state change stream (for auto-login / session restore)
  Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;

  String _mapAuthError(String message) {
    if (message.contains('Invalid login credentials')) {
      return 'غلط یوزر نیم یا پاس ورڈ';
    }
    if (message.contains('Email not confirmed')) {
      return 'ای میل کی تصدیق نہیں ہوئی';
    }
    return 'لاگ ان میں خرابی: $message';
  }
}
```

### Step 1.6 — Update `AuthProvider` to use `AuthRepository`

```dart
// lib/providers/auth_provider.dart
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repo = ref.read(authRepositoryProvider);
  return AuthNotifier(repo);
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;

  AuthNotifier(this._repo) : super(AuthState.initial()) {
    _init();
  }

  void _init() {
    // Listen to Supabase auth state changes (handles session restore)
    _repo.authStateChanges.listen((event) async {
      if (event.event == AuthChangeEvent.signedIn) {
        final user = await _repo.getCurrentUser();
        if (user != null) state = AuthState.authenticated(user);
      } else if (event.event == AuthChangeEvent.signedOut) {
        state = AuthState.unauthenticated();
      }
    });
  }

  Future<bool> login({required String email, required String password}) async {
    try {
      state = AuthState.loading();
      final user = await _repo.signIn(email: email, password: password);
      state = AuthState.authenticated(user);
      return true;
    } on AuthenticationException catch (e) {
      state = AuthState.error(e.message);
      return false;
    }
  }

  Future<void> logout() async {
    await _repo.signOut();
    state = AuthState.unauthenticated();
  }
}
```

### Step 1.7 — Update `LoginScreen`

Change username field to email field, and replace dummy credential check with riverpod provider call. The navigation logic stays the same — only swap `AuthService.login()` with `ref.read(authNotifierProvider.notifier).login(email: ..., password: ...)`.

---

## 4. Phase 2 — Database Schema

Run all SQL below in **Supabase → SQL Editor**.

### Table: `profiles`
Extends `auth.users` with role-specific data.
```sql
CREATE TABLE public.profiles (
  id           UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  phone        TEXT,
  photo_url    TEXT,
  role         TEXT NOT NULL CHECK (role IN ('admin', 'teacher', 'parent')),
  is_active    BOOLEAN DEFAULT TRUE,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW()
);

-- Auto-create profile on new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, name, role)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'name', new.email),
    COALESCE(new.raw_app_meta_data->>'role', 'teacher')
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
```

### Table: `darjas` (درجے — Class Levels)
```sql
CREATE TABLE public.darjas (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,              -- e.g. 'درجہ اول'
  name_en     TEXT,                       -- e.g. 'Grade 1'
  order_num   INT NOT NULL,               -- for sorting
  is_active   BOOLEAN DEFAULT TRUE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

### Table: `classes`
```sql
CREATE TABLE public.classes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  darja_id    UUID REFERENCES public.darjas(id) ON DELETE SET NULL,
  name        TEXT NOT NULL,              -- e.g. 'جماعت الف'
  teacher_id  UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  capacity    INT DEFAULT 50,
  is_active   BOOLEAN DEFAULT TRUE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

### Table: `students`
```sql
CREATE TABLE public.students (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  roll_no        TEXT UNIQUE NOT NULL,
  name           TEXT NOT NULL,
  father_name    TEXT NOT NULL,
  darja_id       UUID REFERENCES public.darjas(id),
  class_id       UUID REFERENCES public.classes(id),
  parent_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  date_of_birth  DATE,
  date_of_admit  DATE DEFAULT CURRENT_DATE,
  phone          TEXT,
  address        TEXT,
  photo_url      TEXT,
  is_active      BOOLEAN DEFAULT TRUE,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW()
);
```

### Table: `staff`
```sql
CREATE TABLE public.staff (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  name           TEXT NOT NULL,
  father_name    TEXT NOT NULL,
  designation    TEXT NOT NULL,
  department     TEXT,
  phone          TEXT NOT NULL,
  cnic           TEXT,
  salary         NUMERIC(10, 2),
  joining_date   DATE NOT NULL,
  is_active      BOOLEAN DEFAULT TRUE,
  photo_url      TEXT,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW()
);
```

### Table: `attendance`
```sql
CREATE TABLE public.attendance (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id  UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  class_id    UUID NOT NULL REFERENCES public.classes(id),
  teacher_id  UUID NOT NULL REFERENCES public.profiles(id),
  date        DATE NOT NULL DEFAULT CURRENT_DATE,
  status      TEXT NOT NULL CHECK (status IN ('present', 'absent', 'leave')),
  note        TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (student_id, date)               -- one record per student per day
);
```

### Table: `fees`
```sql
CREATE TABLE public.fees (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id     UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  month          TEXT NOT NULL,           -- e.g. '2026-03'
  amount_due     NUMERIC(10, 2) NOT NULL,
  amount_paid    NUMERIC(10, 2) DEFAULT 0,
  due_date       DATE NOT NULL,
  paid_date      DATE,
  status         TEXT NOT NULL CHECK (status IN ('paid', 'partial', 'pending', 'past_due'))
                 GENERATED ALWAYS AS (
                   CASE
                     WHEN amount_paid >= amount_due        THEN 'paid'
                     WHEN amount_paid > 0                  THEN 'partial'
                     WHEN CURRENT_DATE > due_date          THEN 'past_due'
                     ELSE 'pending'
                   END
                 ) STORED,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (student_id, month)
);
```

### Table: `exams`
```sql
CREATE TABLE public.exams (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,             -- e.g. 'امتحان نصف سال'
  class_id    UUID REFERENCES public.classes(id),
  exam_date   DATE NOT NULL,
  total_marks INT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

### Table: `results`
```sql
CREATE TABLE public.results (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  exam_id     UUID NOT NULL REFERENCES public.exams(id) ON DELETE CASCADE,
  student_id  UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  subject     TEXT NOT NULL,
  marks_obtained NUMERIC(6, 2) NOT NULL,
  total_marks    NUMERIC(6, 2) NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (exam_id, student_id, subject)
);
```

### Table: `announcements`
```sql
CREATE TABLE public.announcements (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  target_role TEXT CHECK (target_role IN ('all', 'teacher', 'parent', 'admin')),
  posted_by   UUID REFERENCES public.profiles(id),
  is_active   BOOLEAN DEFAULT TRUE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

### Useful Database Views

```sql
-- Attendance summary per class per day (Admin dashboard)
CREATE VIEW public.attendance_summary AS
SELECT
  a.date,
  c.name          AS class_name,
  d.name          AS darja_name,
  COUNT(*)        AS total,
  SUM(CASE WHEN a.status = 'present' THEN 1 ELSE 0 END) AS present_count,
  SUM(CASE WHEN a.status = 'absent'  THEN 1 ELSE 0 END) AS absent_count,
  SUM(CASE WHEN a.status = 'leave'   THEN 1 ELSE 0 END) AS leave_count
FROM public.attendance a
JOIN public.students s ON a.student_id = s.id
JOIN public.classes   c ON a.class_id  = c.id
JOIN public.darjas    d ON s.darja_id  = d.id
GROUP BY a.date, c.name, d.name;

-- Fee summary per student (Parent dashboard)
CREATE VIEW public.fee_summary AS
SELECT
  f.student_id,
  s.name          AS student_name,
  s.roll_no,
  SUM(f.amount_due)  AS total_due,
  SUM(f.amount_paid) AS total_paid,
  SUM(f.amount_due - f.amount_paid) AS outstanding
FROM public.fees f
JOIN public.students s ON f.student_id = s.id
GROUP BY f.student_id, s.name, s.roll_no;
```

---

## 5. Phase 3 — Row Level Security (RLS) Policies

Enable RLS on every table, then grant access via policies.

```sql
-- Enable RLS on all tables
ALTER TABLE public.profiles     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fees         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.results      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.darjas       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classes      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

-- Helper function: get current user role from app_metadata
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS TEXT AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role');
$$ LANGUAGE sql STABLE;
```

### Profiles Policies
```sql
-- Users can view their own profile
CREATE POLICY "users_view_own_profile" ON public.profiles
  FOR SELECT USING (auth.uid() = id);

-- Admins can view all profiles
CREATE POLICY "admin_view_all_profiles" ON public.profiles
  FOR SELECT USING (public.get_user_role() = 'admin');

-- Admins can update all profiles
CREATE POLICY "admin_update_profiles" ON public.profiles
  FOR UPDATE USING (public.get_user_role() = 'admin');

-- Users can update their own profile
CREATE POLICY "users_update_own_profile" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);
```

### Students Policies
```sql
-- Admins: full access
CREATE POLICY "admin_all_students" ON public.students
  FOR ALL USING (public.get_user_role() = 'admin');

-- Teachers: can view students in their classes only
CREATE POLICY "teacher_view_students" ON public.students
  FOR SELECT USING (
    public.get_user_role() = 'teacher'
    AND class_id IN (
      SELECT id FROM public.classes WHERE teacher_id = auth.uid()
    )
  );

-- Parents: can view only their own children
CREATE POLICY "parent_view_own_children" ON public.students
  FOR SELECT USING (
    public.get_user_role() = 'parent'
    AND parent_user_id = auth.uid()
  );
```

### Attendance Policies
```sql
-- Admins: full access
CREATE POLICY "admin_all_attendance" ON public.attendance
  FOR ALL USING (public.get_user_role() = 'admin');

-- Teachers: insert/update/select for their own classes
CREATE POLICY "teacher_manage_attendance" ON public.attendance
  FOR ALL USING (
    public.get_user_role() = 'teacher'
    AND teacher_id = auth.uid()
  );

-- Parents: view attendance of their children only
CREATE POLICY "parent_view_child_attendance" ON public.attendance
  FOR SELECT USING (
    public.get_user_role() = 'parent'
    AND student_id IN (
      SELECT id FROM public.students WHERE parent_user_id = auth.uid()
    )
  );
```

### Fees Policies
```sql
-- Admins: full access
CREATE POLICY "admin_all_fees" ON public.fees
  FOR ALL USING (public.get_user_role() = 'admin');

-- Parents: view their children's fees only
CREATE POLICY "parent_view_own_fees" ON public.fees
  FOR SELECT USING (
    public.get_user_role() = 'parent'
    AND student_id IN (
      SELECT id FROM public.students WHERE parent_user_id = auth.uid()
    )
  );

-- Teachers: read-only view of fees (for info only; no write access)
CREATE POLICY "teacher_view_fees" ON public.fees
  FOR SELECT USING (public.get_user_role() = 'teacher');
```

### Results Policies
```sql
-- Admins: full access
CREATE POLICY "admin_all_results" ON public.results
  FOR ALL USING (public.get_user_role() = 'admin');

-- Teachers: manage results for their own exam/classes
CREATE POLICY "teacher_manage_results" ON public.results
  FOR ALL USING (
    public.get_user_role() = 'teacher'
    AND exam_id IN (
      SELECT id FROM public.exams WHERE class_id IN (
        SELECT id FROM public.classes WHERE teacher_id = auth.uid()
      )
    )
  );

-- Parents: view their children's results only
CREATE POLICY "parent_view_child_results" ON public.results
  FOR SELECT USING (
    public.get_user_role() = 'parent'
    AND student_id IN (
      SELECT id FROM public.students WHERE parent_user_id = auth.uid()
    )
  );
```

### Announcements Policies
```sql
-- All authenticated users can read announcements for their role
CREATE POLICY "read_announcements" ON public.announcements
  FOR SELECT USING (
    is_active = TRUE
    AND (target_role = 'all' OR target_role = public.get_user_role())
  );

-- Only admins can manage announcements
CREATE POLICY "admin_manage_announcements" ON public.announcements
  FOR ALL USING (public.get_user_role() = 'admin');
```

### Darjas & Classes (Read-only for non-admins)
```sql
CREATE POLICY "all_read_darjas"   ON public.darjas   FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "all_read_classes"  ON public.classes  FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "admin_manage_darjas"  ON public.darjas  FOR ALL USING (public.get_user_role() = 'admin');
CREATE POLICY "admin_manage_classes" ON public.classes FOR ALL USING (public.get_user_role() = 'admin');
```

---

## 6. Phase 4 — Storage Buckets

Go to **Supabase → Storage** and create these buckets:

| Bucket Name      | Public? | Purpose                          |
|------------------|---------|----------------------------------|
| `student-photos` | No      | Student profile photos           |
| `staff-photos`   | No      | Staff profile photos             |
| `documents`      | No      | Fee receipts, reports (PDF)      |

### Storage Policies

```sql
-- student-photos: admins can upload/delete; authenticated users can view
CREATE POLICY "admin_upload_student_photos"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'student-photos' AND public.get_user_role() = 'admin');

CREATE POLICY "auth_view_student_photos"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'student-photos' AND auth.role() = 'authenticated');

CREATE POLICY "admin_delete_student_photos"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'student-photos' AND public.get_user_role() = 'admin');
```

Apply similar policies for `staff-photos` and `documents`.

### Flutter Upload Example
```dart
// lib/data/repositories/storage_repository.dart
class StorageRepository {
  final _client = SupabaseService.client;

  Future<String> uploadStudentPhoto({
    required String studentId,
    required File imageFile,
  }) async {
    final fileName = '$studentId-${DateTime.now().millisecondsSinceEpoch}.jpg';
    final path = 'students/$fileName';

    await _client.storage
        .from('student-photos')
        .upload(path, imageFile, fileOptions: const FileOptions(upsert: true));

    return _client.storage.from('student-photos').getPublicUrl(path);
    // Note: for private buckets use createSignedUrl() instead
  }
}
```

---

## 7. Phase 5 — Flutter Integration Layer

### Step 5.1 — New Directory Structure

```
lib/
├── core/
│   ├── config/
│   │   └── supabase_config.dart       ← NEW
│   ├── services/
│   │   ├── supabase_service.dart      ← NEW (replaces auth_service.dart)
│   │   ├── storage_service.dart       ← keep (SharedPreferences)
│   │   └── network_service.dart       ← keep
│   └── utils/
│       └── error_handler.dart         ← extend with SupabaseException
├── data/
│   ├── models/                        ← replace Mock* with real models
│   │   ├── student_model.dart         ← replace MockStudent
│   │   ├── staff_model.dart           ← replace MockStaff
│   │   ├── fee_model.dart             ← replace MockFeeRecord
│   │   ├── attendance_model.dart      ← NEW
│   │   └── result_model.dart          ← replace MockResult
│   ├── repositories/                  ← NEW folder
│   │   ├── auth_repository.dart
│   │   ├── student_repository.dart
│   │   ├── staff_repository.dart
│   │   ├── attendance_repository.dart
│   │   ├── fee_repository.dart
│   │   ├── result_repository.dart
│   │   └── storage_repository.dart
│   └── mock_data/                     ← keep during transition
├── providers/
│   ├── auth_provider.dart             ← update to use AuthRepository
│   ├── attendance_provider.dart       ← update to use AttendanceRepository
│   ├── student_provider.dart          ← NEW
│   ├── fee_provider.dart              ← NEW
│   └── staff_provider.dart            ← NEW
└── presentation/                      ← minimal changes (only data binding)
```

### Step 5.2 — Real Model (example: Student)

```dart
// lib/data/models/student_model.dart
class Student {
  final String id;
  final String rollNo;
  final String name;
  final String fatherName;
  final String darjaId;
  final String darjaName;
  final String classId;
  final String className;
  final String? parentUserId;
  final String? photoUrl;
  final bool isActive;

  const Student({...});

  factory Student.fromJson(Map<String, dynamic> json) => Student(
    id:           json['id'] as String,
    rollNo:       json['roll_no'] as String,
    name:         json['name'] as String,
    fatherName:   json['father_name'] as String,
    darjaId:      json['darja_id'] as String,
    darjaName:    (json['darjas'] as Map?)?['name'] as String? ?? '',
    classId:      json['class_id'] as String,
    className:    (json['classes'] as Map?)?['name'] as String? ?? '',
    parentUserId: json['parent_user_id'] as String?,
    photoUrl:     json['photo_url'] as String?,
    isActive:     json['is_active'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'roll_no':        rollNo,
    'name':           name,
    'father_name':    fatherName,
    'darja_id':       darjaId,
    'class_id':       classId,
    'parent_user_id': parentUserId,
    'photo_url':      photoUrl,
    'is_active':      isActive,
  };
}
```

### Step 5.3 — Repository (example: Attendance)

```dart
// lib/data/repositories/attendance_repository.dart
class AttendanceRepository {
  final _client = SupabaseService.client;

  /// Fetch all students for a class with today's attendance pre-loaded
  Future<List<AttendanceRecord>> getClassAttendance({
    required String classId,
    required DateTime date,
  }) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final response = await _client
        .from('students')
        .select('id, name, roll_no, attendance(status, note)')
        .eq('class_id', classId)
        .eq('is_active', true)
        .eq('attendance.date', dateStr);

    return (response as List)
        .map((row) => AttendanceRecord.fromJson(row))
        .toList();
  }

  /// Upsert attendance (insert or update on conflict)
  Future<void> saveAttendance({
    required String studentId,
    required String classId,
    required String teacherId,
    required DateTime date,
    required String status,  // 'present' | 'absent' | 'leave'
    String? note,
  }) async {
    await _client.from('attendance').upsert({
      'student_id': studentId,
      'class_id':   classId,
      'teacher_id': teacherId,
      'date':       DateFormat('yyyy-MM-dd').format(date),
      'status':     status,
      'note':       note,
    }, onConflict: 'student_id, date');
  }

  /// Subscribe to realtime attendance changes for a class
  RealtimeChannel subscribeToAttendance({
    required String classId,
    required void Function(Map<String, dynamic>) onUpdate,
  }) {
    return _client
        .channel('attendance-$classId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'class_id',
            value: classId,
          ),
          callback: (payload) => onUpdate(payload.newRecord),
        )
        .subscribe();
  }
}
```

### Step 5.4 — Provider (example: Attendance with Riverpod AsyncNotifier)

```dart
// lib/providers/attendance_provider.dart
final attendanceProvider = AsyncNotifierProvider
    .family<AttendanceNotifier, List<AttendanceRecord>, AttendanceParams>(
  AttendanceNotifier.new,
);

class AttendanceNotifier
    extends FamilyAsyncNotifier<List<AttendanceRecord>, AttendanceParams> {
  late AttendanceRepository _repo;

  @override
  Future<List<AttendanceRecord>> build(AttendanceParams params) async {
    _repo = ref.read(attendanceRepositoryProvider);
    return _repo.getClassAttendance(
      classId: params.classId,
      date: params.date,
    );
  }

  Future<void> updateStatus({
    required String studentId,
    required AttendanceStatus status,
  }) async {
    // Optimistic update
    state = state.whenData((list) => list.map((r) {
      if (r.studentId == studentId) return r.copyWith(status: status);
      return r;
    }).toList());

    // Persist to Supabase
    await _repo.saveAttendance(
      studentId: studentId,
      classId: arg.classId,
      teacherId: ref.read(currentUserProvider)!.id,
      date: arg.date,
      status: status.name,
    );
  }
}
```

---

## 8. Phase 6 — Migrating Mock Data to Supabase

### Step 6.1 — Seed Script (Supabase SQL)

Translate the existing `mock_data/mock_students.dart` hard-coded data into a SQL seed file. Run once:

```sql
-- Seed darjas (class levels)
INSERT INTO public.darjas (id, name, name_en, order_num) VALUES
  (gen_random_uuid(), 'درجہ اول',   'Grade 1', 1),
  (gen_random_uuid(), 'درجہ دوم',   'Grade 2', 2),
  (gen_random_uuid(), 'درجہ سوم',   'Grade 3', 3),
  (gen_random_uuid(), 'درجہ چہارم', 'Grade 4', 4),
  (gen_random_uuid(), 'درجہ پنجم',  'Grade 5', 5);

-- After inserting darjas, note their IDs to use below.
-- Seed students (example — expand for all mock students)
INSERT INTO public.students (roll_no, name, father_name, darja_id, class_id, is_active)
SELECT
  'D1-' || LPAD(n::TEXT, 3, '0'),
  CASE n
    WHEN 1 THEN 'محمد عمر'
    WHEN 2 THEN 'احمد علی'
    -- ...add all mock names
  END,
  'محمد اکبر',
  (SELECT id FROM public.darjas WHERE order_num = 1),
  (SELECT id FROM public.classes WHERE name = 'جماعت الف'),
  TRUE
FROM generate_series(1, 30) AS n;
```

**Alternatively**, create a one-time Dart script in `scripts/seed_supabase.dart` that reads `MockStudents.getDarjaAwwalStudents()` and uploads them via the Supabase client. This is more maintainable.

### Step 6.2 — Transition Strategy (Strangler Fig Pattern)

Run mock data and Supabase in parallel during transition:

1. **Flag-based switching** — Add a `kUseSupabase` constant in `lib/core/config/app_config.dart`:
   ```dart
   const bool kUseSupabase = bool.fromEnvironment('USE_SUPABASE', defaultValue: false);
   ```
   
2. **Repository abstraction** — Each repository has an interface:
   ```dart
   abstract class IStudentRepository {
     Future<List<Student>> getStudentsByClass(String classId);
     Future<Student?> getStudentById(String id);
     Future<void> upsertStudent(Student student);
   }
   
   class MockStudentRepository implements IStudentRepository { ... }  // uses MockStudents
   class SupabaseStudentRepository implements IStudentRepository { ... }  // uses Supabase
   ```
   
3. **Provider toggles** between implementations:
   ```dart
   final studentRepositoryProvider = Provider<IStudentRepository>((ref) {
     return kUseSupabase
         ? SupabaseStudentRepository()
         : MockStudentRepository();
   });
   ```

4. Switch `kUseSupabase` to `true` only after full testing.

---

## 9. Phase 7 — Realtime & Offline Support

### Realtime (Live Attendance Board)

```dart
// In AttendanceScreen initState
late RealtimeChannel _channel;

@override
void initState() {
  super.initState();
  _channel = attendanceRepo.subscribeToAttendance(
    classId: widget.classId,
    onUpdate: (record) {
      ref.read(attendanceProvider.notifier).handleRemoteUpdate(record);
    },
  );
}

@override
void dispose() {
  _channel.unsubscribe();
  super.dispose();
}
```

### Offline Support

1. **Local cache with `SharedPreferences`** (already in place) — When Supabase call fails:
   ```dart
   Future<List<Student>> getStudents(String classId) async {
     try {
       final data = await _client.from('students').select().eq('class_id', classId);
       // Cache to SharedPreferences
       await StorageService.saveString('students_$classId', jsonEncode(data));
       return data.map(Student.fromJson).toList();
     } catch (_) {
       // Fallback to cache
       final cached = StorageService.getString('students_$classId');
       if (cached != null) return (jsonDecode(cached) as List).map(Student.fromJson).toList();
       rethrow;
     }
   }
   ```

2. **Pending sync queue** — Store unsent attendance records locally. Replay when connectivity returns (use `NetworkService.connectionStatus` stream already in the codebase).

---

## 10. Phase 8 — Environment & Security Hardening

### Step 8.1 — Flutter Obfuscation
In `android/app/build.gradle.kts`:
```kotlin
buildTypes {
  release {
    isMinifyEnabled = true
    isShrinkResources = true
  }
}
```
Build with: `flutter build apk --obfuscate --split-debug-info=debug_symbols/`

### Step 8.2 — Certificate Pinning (optional but recommended)
Use `http_certificate_pinning` or configure `dio` with pinned certificates for network calls to Supabase.

### Step 8.3 — Supabase API Key Rotation
- Never commit the anon key to Git.
- Use `flutter_dotenv` + `.env` in `assets/` (excluded from Git via `.gitignore`).
- For CI/CD, inject via environment variables.

### Step 8.4 — Auth Session Security
- Set JWT expiry to `3600s` (1 hour) in Supabase → Settings → Auth.
- Enable **Refresh Token Rotation**.
- Use `AuthFlowType.pkce` (already in `SupabaseService`).

### Step 8.5 — Input Sanitization
- All user inputs are already validated via `lib/core/utils/validators.dart`.
- Supabase PostgREST uses parameterized queries — no SQL injection risk.
- Sanitize file upload names before passing to Storage.

### Step 8.6 — Database Backups
- Enable **Point-in-time recovery** in Supabase (Pro plan).
- Schedule weekly exports via pg_dump for free tier.

---

## 11. Migration Checklist

### Phase 0 — Setup
- [ ] Create Supabase project
- [ ] Copy Project URL & anon key
- [ ] Create `assets/.env` and add to `.gitignore`
- [ ] Add `supabase_flutter`, `flutter_dotenv`, `cached_network_image`, `uuid` to `pubspec.yaml`
- [ ] Run `flutter pub get`
- [ ] Call `SupabaseService.init()` in `main.dart`

### Phase 1 — Authentication
- [ ] Enable Email/Password auth in Supabase dashboard
- [ ] Set `app_metadata.role` for each user
- [ ] Create `profiles` table + trigger
- [ ] Create `AuthRepository`
- [ ] Update `AuthProvider` to use `AuthRepository`
- [ ] Update `LoginScreen` to use email field
- [ ] Test login for all 3 roles

### Phase 2 — Database
- [ ] Run schema SQL: `darjas`, `classes`, `students`, `staff`
- [ ] Run schema SQL: `attendance`, `fees`, `exams`, `results`
- [ ] Run schema SQL: `announcements`
- [ ] Create `attendance_summary` view
- [ ] Create `fee_summary` view

### Phase 3 — RLS
- [ ] Enable RLS on all tables
- [ ] Create helper function `get_user_role()`
- [ ] Apply all role-based policies
- [ ] Test policies with Supabase Policy Tester

### Phase 4 — Storage
- [ ] Create `student-photos` bucket
- [ ] Create `staff-photos` bucket
- [ ] Create `documents` bucket
- [ ] Add storage RLS policies
- [ ] Implement `StorageRepository.uploadStudentPhoto()`

### Phase 5 — Flutter Layer
- [ ] Create `lib/data/repositories/` folder
- [ ] Replace `MockStudent` with `Student` model
- [ ] Replace `MockStaff` with `Staff` model
- [ ] Replace `MockFeeRecord` with `Fee` model
- [ ] Replace `MockResult` with `Result` model
- [ ] Implement `StudentRepository`
- [ ] Implement `AttendanceRepository`
- [ ] Implement `FeeRepository`
- [ ] Implement `StaffRepository`
- [ ] Implement `ResultRepository`
- [ ] Update all providers to `AsyncNotifier`

### Phase 6 — Migration
- [ ] Seed `darjas` data
- [ ] Seed `classes` data
- [ ] Create staff user accounts in Supabase Auth
- [ ] Seed `students` table
- [ ] Link students to parent user accounts
- [ ] Set `kUseSupabase = true`
- [ ] Remove mock data files

### Phase 7 — Realtime & Offline
- [ ] Subscribe to attendance realtime updates
- [ ] Implement local cache fallback in repositories
- [ ] Implement pending-sync queue for offline saves

### Phase 8 — Security
- [ ] Enable build obfuscation
- [ ] Configure JWT expiry + refresh rotation
- [ ] Verify no secrets in Git history
- [ ] Run Supabase security advisors

---

## 12. File-by-File Change Summary

| File | Action | Notes |
|------|--------|-------|
| `pubspec.yaml` | **Modify** | Add `supabase_flutter`, `flutter_dotenv`, `cached_network_image`, `uuid` |
| `assets/.env` | **Create** | Supabase URL + anon key. Add to `.gitignore` |
| `lib/main.dart` | **Modify** | Add `SupabaseService.init()` before `runApp` |
| `lib/core/services/supabase_service.dart` | **Create** | Supabase init + client accessor |
| `lib/core/services/auth_service.dart` | **Replace** | Replaced by `AuthRepository` |
| `lib/core/utils/error_handler.dart` | **Modify** | Add `SupabaseException` mapping |
| `lib/data/models/student_model.dart` | **Replace** | `MockStudent` → `Student` with `fromJson/toJson` |
| `lib/data/models/staff_model.dart` | **Replace** | `MockStaff` → `Staff` |
| `lib/data/models/fee_model.dart` | **Replace** | `MockFeeRecord` → `Fee` |
| `lib/data/models/attendance_model.dart` | **Create** | New `AttendanceRecord` model |
| `lib/data/models/result_model.dart` | **Replace** | `MockResult` → `Result` |
| `lib/data/repositories/auth_repository.dart` | **Create** | Supabase Auth wrapper |
| `lib/data/repositories/student_repository.dart` | **Create** | CRUD for students |
| `lib/data/repositories/attendance_repository.dart` | **Create** | Attendance CRUD + realtime |
| `lib/data/repositories/fee_repository.dart` | **Create** | Fee management |
| `lib/data/repositories/staff_repository.dart` | **Create** | Staff CRUD |
| `lib/data/repositories/storage_repository.dart` | **Create** | Photo upload/download |
| `lib/data/mock_data/` | **Remove** | After migration verified |
| `lib/providers/auth_provider.dart` | **Modify** | Use `AuthRepository` |
| `lib/providers/attendance_provider.dart` | **Modify** | Use `AttendanceRepository` + `AsyncNotifier` |
| `lib/providers/student_provider.dart` | **Create** | New provider |
| `lib/providers/fee_provider.dart` | **Create** | New provider |
| `lib/providers/staff_provider.dart` | **Create** | New provider |
| `lib/presentation/screens/auth/login_screen.dart` | **Modify** | Email field, use `authNotifierProvider` |
| `lib/presentation/screens/admin/*.dart` | **Modify** | Replace mock data with provider async consumers |
| `lib/presentation/screens/teacher/*.dart` | **Modify** | Same as above |
| `lib/presentation/screens/parent/*.dart` | **Modify** | Same as above |

---

> **Estimated effort:** 4–6 weeks for a single developer following these phases sequentially.  
> **Recommended order:** Phase 0 → 1 → 2 → 3 → 5 → 6 → 4 → 7 → 8  
> Start with Auth since everything else depends on it. Database + RLS can be done in parallel with the Flutter layer once the schema is finalized.
