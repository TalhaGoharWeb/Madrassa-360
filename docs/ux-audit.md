# Madrassa 360 — UI/UX Audit (Phase 1, read-only)

**Repo:** `TalhaGoharWeb/Madrassa-360` (branch `main`, audited 2026-09-28)
**Scope:** all 64 `.dart` files under `lib/presentation/screens/` (+ the shared nav widgets).
**Method:** static inspection of screens, navigation shells, routes, labels, and components. Nothing in the repo was changed.

---

## 1. Screen inventory

### 1.1 Auth (`lib/presentation/screens/auth/`, 5 files)
| File | Purpose |
|---|---|
| `auth_gate.dart` | Cold-start router: branded splash → restore session → Login / RoleHome / TenantPicker / NoAccess |
| `login_screen.dart` | Urdu login form (email, password, remember-me, forgot-password link); pushReplacement into the app on success |
| `forgot_password_screen.dart` | Password-reset flow |
| `tenant_picker_screen.dart` | Multi-tenant chooser for users belonging to several madrasas |
| `no_access_screen.dart` | Shown when an authenticated user has no tenant/role |

### 1.2 Role dashboards (`screens/dashboards/`, 13 files)
| File | Purpose |
|---|---|
| `role_home.dart` | Post-login router. Maps role keys → dashboard (clerk/accountant/academic/hostel/library/exam → dedicated dashboards; teachers → TeacherHome; parent/student → GenericDashboard; principal-authority → PrincipalDashboard). Never renders blank. |
| `teacher_home.dart` | Teacher bottom-nav shell (permission-gated tabs: ڈیش بورڈ، میری جماعتیں، میرے طلبہ، حاضری، امتحانات، نتائج). Uses the standard `BottomNavigationBar`. |
| `teacher_dashboard.dart` | Teacher's home tab: quick actions (حاضری لگائیں، طلبہ دیکھیں، نمبر درج کریں), my classes / my students / today's attendance / today's lessons sections. |
| `my_classes_screen.dart` | Teacher's assigned classes; tapping a class opens it. |
| `my_students_screen.dart` | Students in the teacher's assigned classes. |
| `principal_dashboard.dart` | Phase-7a principal home (DashboardScaffold): آج مدرسے کا حال stats, اہم امور alerts (each with an action), quick actions (داخلہ، استاد شامل کریں، اعلان، فیس وصول، امتحان بنائیں، رپورٹ). Sections self-gate on permissions + enabled modules. |
| `clerk_dashboard.dart` | دفتر: new admissions, pending admissions, today's fee collection, missing documents; quick actions (نیا داخلہ، طلبہ کی فہرست، فیس وصول کریں، رسید بنائیں، داخلے مکمل کریں، رسیدیں تیار کریں). |
| `accountant_dashboard.dart` | مالیات: today's collection, today's expenses, pending fees, cash; actions (فیس وصول کریں، رسید بنائیں، خرچ درج کریں، آمدن درج کریں، حساب دیکھیں، مالی رپورٹ، تفصیلی حسابات). |
| `academic_admin_dashboard.dart` | تعلیمی نظام (ناظمِ تعلیم/ناظمِ حفظ): درجات، اساتذہ، طلبہ، آج حاضری، pending results; actions (استاد مقرر کریں، جماعت بنائیں، امتحان بنائیں، نتائج دیکھیں). |
| `hostel_dashboard.dart` | دارالاقامہ: resident students, today's present, on leave, absent; actions (حاضری، رپورٹ). |
| `library_dashboard.dart` | کتب خانہ: total books, issued, pending returns; actions (کتب، کتاب جاری کریں، کتاب واپس لیں، تلاش کریں، رپورٹ). |
| `exam_dashboard.dart` | امتحانات (ممتحن): ongoing exams, marks pending, results ready, published; actions (امتحان بنائیں، نمبر درج کریں، نتائج دیکھیں، رپورٹ). |
| `exam_wizard_screen.dart` | **8-step guided exam creation**: امتحان بنائیں → مضامین → طلبہ → نمبر درج کریں → جانچ کریں → نتیجہ تیار کریں → منظوری → شائع کریں. Real persistence at each step; one step visible at a time. |

### 1.3 Admin (`screens/admin/`, 10 files)
| File | Purpose |
|---|---|
| `admin_dashboard_screen.dart` | Legacy grid-style admin home: greeting header, permission-filtered stat cards (کل طلباء، اساتذہ، جماعتیں، واجب الادا، آج حاضر، کل عملہ), recent activity, and a ماڈیولز grid linking to درجات، اعلانات، کتب خانہ، مالیات، حاضری، نتائج، عملہ، رپورٹس، بیک اپ، اطلاعات. **BUG: the عملہ (Staff) module card navigates to `const Placeholder()`** — StaffListScreen is imported but never wired. |
| `admin_main_screen.dart` | **DEAD** — permission-driven bottom-nav shell (buildNavTabs via role_config). No live references. |
| `student_list_screen.dart` | (1274 lines) Full student directory: search, filter chips (class filters), list; **نیا داخلہ** via a long `AlertDialog` form (photo picker, name, father name, phone, class/section dropdowns, address). |
| `staff_list_screen.dart` | (929 lines) Staff directory with search + add/edit forms. |
| `darja_screen.dart` | درجات management: class/section list, نیا درجہ dialog. |
| `fee_management_screen.dart` | (1156 lines) 2 tabs: فیس کی تفصیل (fee list w/ error/empty states) and وصولی (collections). Collect-fee via `showModalBottomSheet` + confirmation `showDialog`; حالیہ وصولی list. |
| `finance_screen.dart` | مالیات ledger: نئی اندراج dialog, summary tiles, ledger cards. |
| `library_screen.dart` | Books + issues: نئی کتاب dialog, کتاب جاری کریں dialog, issues list. |
| `user_management_screen.dart` | **LEGACY** "صارف انتظام" — 2 tabs (صارفین / کردار و اجازتیں). Still the screen reached from the principal's quick action, the admin dashboard module card, and `admin_main_screen`. Duplicated by the newer Phase-8a hub. |
| `backup_screen.dart` | One-file backup / restore / delete with validation list. Titles are mixed bilingual (`بیک اپ / Backup`, `حذف کریں؟ / Delete?`) — inconsistent with the rest of the app. |

### 1.4 Teacher (`screens/teacher/`, 3 files)
| File | Purpose |
|---|---|
| `attendance_screen.dart` | (786 lines) Class dropdown, date picker, bulk actions (سب کو حاضر کریں / سب کو غیر حاضر کریں / صاف کریں), per-student status selector rows, extended **FAB = حاضری محفوظ کریں**. Fails closed (no tenant/class → message). |
| `results_screen.dart` | (1159 lines) 2 tabs: نتائج (view) + نتیجہ درج کریں (entry: class + exam-type dropdowns → marks entry). |
| `teacher_dashboard_screen.dart` | **DEAD** — a *second* class also named `TeacherDashboardScreen` (same class name as `dashboards/teacher_dashboard.dart`, different file). Referenced only by dead `main_screen.dart`. |

### 1.5 Parent (`screens/parent/`, 3 files)
| File | Purpose |
|---|---|
| `parent_main_screen.dart` | Parent bottom-nav shell: ہوم / فیس / پروفائل (custom InkWell nav, same code as dead MainScreen). |
| `parent_dashboard_screen.dart` | Child selector, child profile card, quick stats (اس ماہ حاضری، امتحانی نمبر، فیس کی حالت), today's update, activity timeline (currently an empty section), upcoming exams. |
| `fee_history_screen.dart` | Parent's fee records with empty state (`کوئی فیس ریکارڈ نہیں`). |

### 1.6 Common (`screens/common/`, 5 files)
| File | Purpose |
|---|---|
| `announcements_screen.dart` | Broadcast announcements feed + نیا اعلان composer (with pin option). |
| `notifications_screen.dart` | Notifications inbox. Carries its own **per-screen Urdu/English toggle** (app bar button) — only 2 screens in the app do this. |
| `profile_screen.dart` | (888 lines) Profile header + settings groups: edit profile, notification switches, **language (اردو / English)**, and an **انتظام** section that is the *only* entry point to صارفین اور ذمہ داریاں (user mgmt hub) and اختیار سونپنا (delegation). Also: help, about, logout. |
| `dashboard_guide_screen.dart` | Per-role usage guide, reachable via `DashboardGuideButton` on dashboards. |
| `about_screen.dart` | About/developer info; also has the Urdu/English toggle. |

### 1.7 Reports (`screens/reports/`, 1 file)
| `reports_hub_screen.dart` | (544 lines) Report catalogue (titleUr + titleEn + descriptionUr), filter bottom sheet, preview / print / save / share / CSV / Excel actions, PDF preview screen. |

### 1.8 Settings / user administration (`screens/settings/`, 7 files)
| File | Purpose |
|---|---|
| `user_management_hub.dart` | **Phase-8a hub** "صارفین اور ذمہ داریاں": search, 2 tabs (صارفین / ذمہ داریاں read-only), bulk role change, FAB → user wizard; overflow menu → ڈیٹا حدود (scope manager). |
| `user_wizard_screen.dart` | (982 lines) Create-user wizard. |
| `user_detail_screen.dart` | User detail (entry to per-user actions). |
| `role_ux_widgets.dart` | Shared role-UX components. |
| `scope_manager_screen.dart` | "ڈیٹا حدود": scoped-access directory + `ScopeEditorScreen` (دائرہ کار مقرر کریں). 838 lines; deep (hub → scope manager → scope editor). |
| `delegation_screen.dart` | "اختیار سونپنا": delegation list, empty state, revoke dialog. |
| `delegation_create_screen.dart` | Create a temporary delegation. |

### 1.9 Super admin (`screens/super_admin/`, 4 files) — **all deprecated**
| File | Purpose |
|---|---|
| `super_admin_main_screen.dart` | @Deprecated bottom-nav shell (NavigationBar, the *third* nav idiom). No live references. |
| `super_admin_dashboard_screen.dart` | Network summary (کل مدارس، فعال، پریمیم، اسٹینڈرڈ) + madrasa list; still referenced by the deprecated shell only. |
| `madrasa_management_screen.dart` | Madrasa CRUD with search; نئے مدرسہ / ترمیم dialogs; manual `textDirection: rtl` overrides (predates app-wide RTL). |

### 1.10 Master admin / platform console (`screens/master_admin/`, 12 files)
| File | Purpose |
|---|---|
| `master_admin_shell.dart` | Platform console at route `/master` (guarded). **Drawer** navigation (the *fourth* nav idiom), AppBar entirely in **English**: 'Platform Owner Console' / 'Platform Admin Console', 'Back to app'. `_backToApp` falls back to dead `MainScreen` when the stack is empty. |
| `master_dashboard_screen.dart` | Platform KPIs. |
| `madrasa_list_screen.dart` | Tenant list. |
| `madrasa_detail_screen.dart` | Per-tenant detail incl. suspend / expiry / broadcast controls. |
| `create_madrasa_wizard.dart` | Multi-step tenant creation wizard. |
| `licenses_screen.dart` / `plans_screen.dart` / `subscriptions_screen.dart` | Licensing & billing administration. |
| `modules_screen.dart` | Module catalogue toggles per tenant. |
| `platform_users_screen.dart` | Platform operators. |
| `audit_logs_screen.dart` | Audit trail (explicit RTL override). |
| `widgets/ma_widgets.dart` | Shared console widgets. |

### 1.11 Root-level
| File | Purpose |
|---|---|
| `screens/main_screen.dart` | **DEAD** — legacy teacher bottom-nav shell. Only referenced by `master_admin_shell._backToApp`. |
| `screens/crash_screen.dart` | Bilingual crash/restart screen (explicit RTL override). |

**Widget inventory (nav-relevant):** `widgets/app_drawer.dart` — **dead**, zero usages (module-gated drawer that nothing uses). `widgets/dashboard/` — the shared design system: `dashboard_scaffold.dart` (greeting → schedule → stats → alerts → quick actions), `stat_card.dart`, `alert_card.dart`, `quick_actions.dart`, `day_timeline.dart`, `schedule_slot.dart`, `today_tasks.dart`, `pattern_background.dart`.

---

## 2. Navigation architecture

**Flow:** `AuthGate` (splash → session restore) → `LoginScreen` → `RoleHomeScreen` (role router) → one role shell:

| Role | Shell | Nav pattern |
|---|---|---|
| teacher / ustad | `TeacherHomeScreen` | BottomNavigationBar (permission-gated tabs, min 2) |
| clerk / accountant / academic / hostel / librarian / exam / principal-authority | Dedicated dashboard screens | Single scrolling dashboard; secondary screens pushed via `MaterialPageRoute` |
| parent | `ParentMainScreen` | Custom InkWell bottom bar (ہوم / فیس / پروفائل) |
| platform operator | `MasterAdminShell` (`/master`, guarded) | **Drawer** (8 English items) |
| student / parent-role | `GenericDashboardScreen` | Scrolling dashboard + quick actions |

There is **no named-route table** except `/master`; everything else is `Navigator.push(MaterialPageRoute(...))`.

### Task-depth table (taps from home)
| Task | Path | Depth |
|---|---|---|
| Mark attendance (teacher) | Home → حاضری tab (bottom nav) → pick class/date → rows → FAB save | 1–2 |
| View students (admin) | Dashboard → ماڈیولز grid → … actually students list is not a module card; via clerk dashboard quick action طلبہ کی فہرست, or principal quick action | 2–3, entry point varies by role |
| Collect fee (clerk/accountant) | Dashboard → فیس وصول کریں → bottom sheet → dialog → confirm | 2–3 modals deep |
| Enter results (teacher) | Home → نتائج tab → نتیجہ درج کریں tab → dropdowns → marks | 3 |
| Add student (clerk) | Dashboard → نیا داخلہ → long AlertDialog form | 2 (but the form itself is one very long scroll) |
| Create exam | Exam dashboard → امتحان بنائیں → 8-step wizard | 2 then 8 guided steps |
| Manage users | **Profile tab → انتظام group → صارفین اور ذمہ داریاں** (or principal: home → صارفین quick action → *legacy* screen) | **4 taps, buried**; two different destinations |
| Data scopes | Profile → صارفین اور ذمہ داریاں → overflow → ڈیٹا حدود → دائرہ کار مقرر کریں | 5 |
| Backup | Admin dashboard → ماڈیولز → بیک اپ | 3 (module card buried in scrollable grid) |
| Platform: suspend tenant | /master drawer → Madrasas → tenant → detail controls | 3 |

---

## 3. UX problems

### P0 — Must fix
1. **Two parallel user-management systems.** `admin/user_management_screen.dart` ("صارف انتظام", tabs صارفین / کردار و اجازتیں) is what the principal's quick action, the admin module grid, and admin_main reach; `settings/user_management_hub.dart` ("صارفین اور ذمہ داریاں", newer Phase-8a) is what the profile tile reaches. Different titles, different tabs, different code paths for the same job. Users will learn one and be confused by the other.
2. **Critical bug: عملہ module card → `Placeholder()`.** In `admin_dashboard_screen.dart` the Staff module card navigates to `const Placeholder()` (comment admits StaffListScreen is "imported in outer scope" but never wired). Tapping عملہ shows a blank placeholder — a shipped, user-visible broken button.
3. **Dead navigation shells.** `main_screen.dart`, `admin/admin_main_screen.dart`, `teacher/teacher_dashboard_screen.dart`, `super_admin/*`, `widgets/app_drawer.dart` are unreferenced (or only referenced by each other / a fallback in `master_admin_shell._backToApp`). They confuse the codebase and the audit; worse, the AppBar of the *live* console can push-replace to a dead `MainScreen`.
4. **Terminology drift.** طلبہ (121 uses) vs طلباء (34); ہوم (parent shell, AppStrings) vs ڈیش بورڈ (teacher tabs, role_config); نتائج vs رپورٹس used loosely; "Master admin" console 100% English while the app is Urdu-first; backup screen uses bilingual titles (`بیک اپ / Backup`, `حذف کریں؟ / Delete?`) that appear nowhere else.
5. **Two "home" concepts for admins.** `AdminDashboardScreen` (legacy stat+module grid) and `PrincipalDashboardScreen` (Phase-7a scaffold) overlap heavily (stats, alerts, quick actions, module links) with different visual language. `role_home` routes principal-authority to the new one; the legacy one still exists and is referenced by `AdminMainScreen` (dead) — decide which is canonical and delete the other.

### P1 — Should fix
6. **Four navigation idioms**: custom InkWell Row bars (parent/main/admin_main), `BottomNavigationBar` (teacher_home), `NavigationBar` (dead super admin), Drawer (master console). Standardize on one bottom-nav component + one drawer.
7. **Settings have no home.** There is no Settings screen: notification switches, language, admin tools, backup, user management, delegation are scattered across `profile_screen` (انتظام group), module grids, and dashboard quick actions. Admin settings (backup, modules, scopes) deserve a real ترتیبات area reachable in ≤2 taps, not buried 4–5 deep.
8. **Hidden/discoverable features**: user management (profile → انتظام tile), exam wizard (only from exam dashboard), scope manager (hub overflow menu), backup (module grid). Primary admin workflows should be top-level.
9. **Overloaded screens**: `student_list_screen` (1274 lines: list + filters + full add/edit dialogs), `fee_management_screen` (1156: 2 tabs + sheets + dialogs), `results_screen` (1159: 2 tabs), `user_management_hub` + `user_wizard` (1652 combined). Splitting list vs. editor concerns would simplify each.
10. **Add-student is a long `AlertDialog`** (photo, name, father, phone, class, section, address) — on small phones a bottom-sheet or stepped form (like the exam wizard pattern) fits better and matches the app's own wizard precedent.
11. **Inconsistent form/modal patterns**: add-student = `AlertDialog`; collect-fee = `showModalBottomSheet` + `showDialog`; add-book/add-darja = dialogs. One pattern per platform size.
12. **Announcements vs Notifications are two concepts** (`اعلانات` broadcast + composer vs `اطلاعات` inbox) reached from different places (module grid vs …). A single مرکزِ اطلاعات with tabs would match user mental models; notifications also duplicates announcements visually.
13. **English leakage in an Urdu-first app**: the entire master-admin console (8 drawer items, AppBar title, 'Back to app'), dual-language backup titles, `profile` language tile listing "اردو / English". Decide: console stays English deliberately (document it) or translate — currently it's accidental.
14. **RTL redundancy**: app-wide RTL comes from `locale: ur-PK`, yet `super_admin/*`, `master_admin/*`, `crash_screen`, `profile_screen` carry manual `textDirection: TextDirection.rtl` overrides — dead weight from before app-wide RTL, and a trap for future LTR work.
15. **Weak primary actions in secondary flows**: fee collection's CTA lives inside a bottom sheet behind a tab; receipt generation (رسید بنائیں) is a quick action but not contextual to the collection just completed. Contextual "next step" actions after save are missing in most flows (only attendance's FAB is strong).
16. **Report hub lacks a "my recent reports" state**: catalogue → filters → preview is good, but no history of generated reports.
17. **Parent dashboard has dead sections**: `_buildActivityTimeline` renders an empty section; `_buildUpcomingExams` exists but data-thin. Either wire them or remove them — a parent's home shouldn't show hollow sections.
18. **Student vs teacher vocabulary collision**: `my_students_screen` (میرے طلبہ) for teachers and `student_list_screen` (full directory) for admins — fine, but both are reached as "طلبہ/طلباء" in different labels; keep one plural spelling.
19. **Search coverage is patchy**: students, staff, madrasas, users, library dashboard have search; darja, finance ledger, fee lists, announcements do not. A shared search-field component + consistent placement would fix this cheaply.
20. **No shared empty/loading/error components**: each screen hand-rolls (`'ابھی کوئی وصولی درج نہیں'`, `'فیس لوڈ کرنے میں خطا'`, FutureBuilder error titles). Extract one `EmptyState`/`ErrorState` widget for consistency.

### P2 — Nice to have
21. **Nastaliq vertical cost**: every display style enforces `height ≥ 2.0` (correct for nuqta clipping) — this doubles the vertical rhythm cost on dense screens (module grids, list rows). Dense data rows should prefer Naskh (the system already does for body; enforce it in lists).
22. **Teacher home has 6 tabs** (ڈیش بورڈ، میری جماعتیں، میرے طلبہ، حاضری، امتحانات، نتائج) — میری جماعتیں and میرے طلبہ overlap (class list → students). Merging into طلبہ with a class filter (the admin list pattern) would free a tab.
23. **DashboardScaffold order is fixed** (greeting → schedule → stats → alerts → quick actions) for all 7a dashboards; quick actions sit at the bottom, below the fold on small phones. Consider actions-first or sticky action bar for the 2–3 most-used actions per role.
24. **Master console drawer labels are English** while the app drawer pattern (dead AppDrawer) was Urdu with tenant branding — if operators are Urdu speakers, translate; if English is deliberate for platform staff, note it in the UX spec.
25. **Per-screen language toggle** exists only in notifications + about screens (`_isUrdu` local state) while profile offers a global اردو/English setting — the local toggles fight the global setting. Remove local toggles; honor the global one.

---

## 4. What's GOOD — preserve in the redesign

- **DashboardScaffold design system** (`widgets/dashboard/`): greeting header with tenant branding, schedule slot, stat cards, actionable alerts, quick-action grid. Consistent across all 7 role dashboards — the redesign should *extend* this, not replace it.
- **Permission-gated navigation** (teacher_home tabs, role_home routing, dashboard sections): tabs/sections appear only for held permissions and enabled modules — no dead-end screens, no "coming soon". Keep this contract.
- **Exam wizard** (8 steps, one step visible, real persistence per step): the app's best complex-flow pattern. Reuse it for add-student, create-madrasa, and collect-fee flows.
- **Attendance screen flow**: class/date selectors → bulk actions (سب کو حاضر کریں / صاف کریں) → per-student selector → extended FAB save → offline banner. This is the reference implementation for a "daily task" screen.
- **Reports hub**: catalogue with trilingual titles, filter sheet, پیش نظارہ / پرنٹ / محفوظ کریں / شیئر / CSV / Excel. Solid; add "recent reports".
- **Offline-first honesty**: pending-sync banners (`آف لائن: ہم آہنگی کے منتظر ریکارڈز`), save-failed messages, never-fake-data discipline in dashboards ("Empty feed renders as an empty section (never fake rows)").
- **Tenant branding**: logo + name + primary colour threaded through drawer header, dashboard headers, login — multi-tenancy without per-client edits.
- **Per-role dashboard guides** (`DashboardGuideScreen` + `DashboardGuideButton`): discoverable help; keep and extend.
- **Typography system**: JameelNooriNastaleeq (display, height ≥ 2.0) + NotoNaskhArabic (body), with embedded-font fallbacks so Urdu never falls back to a system font. The contract (Nastaliq ≥15sp, Naskh for dense/long text) is already the right rule.
- **Urdu-first strings discipline**: `AppStrings` centralizes attendance/auth vocabulary — extend it to cover the drift (طلبہ/طلباء, ہوم/ڈیش بورڈ).
- **RoleHome never-blank guarantee** (GenericDashboard with greeting + announcements + profile): good failure UX; keep.

---

## 5. Prioritized redesign recommendations

### P0 (fix before/with redesign)
1. **Unify user management**: retire `admin/user_management_screen.dart`; route *all* entries (principal quick action, module card, admin shell) to `settings/user_management_hub.dart`; one title: «صارفین اور ذمہ داریاں».
2. **Fix the عملہ Placeholder bug** (wire StaffListScreen) — a shipped broken button.
3. **Delete dead shells** (`main_screen.dart`, `admin_main_screen.dart`, `teacher/teacher_dashboard_screen.dart`, `super_admin/*`, `app_drawer.dart`); fix `master_admin_shell._backToApp` fallback to route to RoleHome instead of dead MainScreen.
4. **Freeze the glossary**: طلبہ (not طلباء), ڈیش بورڈ (not ہوم) in nav, one term each for announcements/notifications/scopes/delegation; lint new strings against it.
5. **Choose one admin home** (Phase-7a `PrincipalDashboardScreen`) and remove or repurpose `AdminDashboardScreen`.

### P1 (redesign scope)
6. **One navigation idiom**: standard `BottomNavigationBar` for role shells; one drawer component for the platform console. Delete the custom InkWell bars.
7. **Create a real ترتیبات (Settings) area** per role: notifications, language, backup, modules/scopes (admin), help, about, logout — max 2 taps from home. Profile screen keeps *profile*; settings move out.
8. **Surface hidden features**: user management, delegation, backup, exam wizard as first-class destinations (dashboard quick actions or settings), not 4–5 taps deep.
9. **Adopt the wizard pattern** for add-student (multi-section form) and collect-fee (bottom sheet is fine; add a receipt next-step). Split list screens from their editor dialogs.
10. **Unify announcements + notifications** into one inbox with tabs (اعلانات / اطلاعات); remove per-screen language toggles, honor the global setting.
11. **Standardize states & search**: one `EmptyState`, one `ErrorState`, one `SearchField` used by every list (students, staff, darja, ledger, fees, announcements).

### P2 (polish)
12. Remove manual RTL overrides; document whether the platform console is intentionally English.
13. Move quick actions above the fold (or sticky) on role dashboards.
14. Add "recent reports" to the reports hub; wire/remove the parent dashboard's hollow sections.
15. Enforce Naskh for dense list rows; keep Nastaliq for headings/labels.

---

## Appendix — file map (all 64)

auth/: auth_gate, forgot_password_screen, login_screen, no_access_screen, tenant_picker_screen ·
dashboards/: academic_admin_dashboard, accountant_dashboard, clerk_dashboard, exam_dashboard, exam_wizard_screen, hostel_dashboard, library_dashboard, my_classes_screen, my_students_screen, principal_dashboard, role_home, teacher_dashboard, teacher_home ·
admin/: admin_dashboard_screen, admin_main_screen ☠, backup_screen, darja_screen, fee_management_screen, finance_screen, library_screen, staff_list_screen, student_list_screen, user_management_screen ⚠legacy ·
teacher/: attendance_screen, results_screen, teacher_dashboard_screen ☠ ·
parent/: fee_history_screen, parent_dashboard_screen, parent_main_screen ·
common/: about_screen, announcements_screen, dashboard_guide_screen, notifications_screen, profile_screen ·
reports/: reports_hub_screen ·
settings/: delegation_create_screen, delegation_screen, role_ux_widgets, scope_manager_screen, user_detail_screen, user_management_hub, user_wizard_screen ·
super_admin/: madrasa_management_screen ☠, super_admin_dashboard_screen ☠, super_admin_main_screen ☠ ·
master_admin/: audit_logs_screen, create_madrasa_wizard, licenses_screen, madrasa_detail_screen, madrasa_list_screen, master_admin_shell, master_dashboard_screen, modules_screen, plans_screen, platform_users_screen, subscriptions_screen, widgets/ma_widgets ·
root: crash_screen, main_screen ☠

☠ = dead/unreferenced · ⚠ = legacy duplicate
