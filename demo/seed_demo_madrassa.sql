-- ═══════════════════════════════════════════════════════════════════
-- Madrassa-360 — Demo data pack (SEED)
-- File: demo/seed_demo_madrassa.sql
--
-- Creates ONE demo tenant ('demo-madrassa' / 'ڈیمو مدرسہ') with a complete,
-- realistic dataset covering every major table. Everything is scoped to the
-- single demo tenant, so removal is one script: demo/remove_demo_data.sql.
--
-- ═══ STEP 0 — DEMO LOGINS (create in Supabase Auth BEFORE running) ═══
--   Dashboard → Authentication → Users → Add user → Create new user
--   (tick "Auto Confirm User"). Same password for all five:
--
--     Email                              Role               Password
--     ─────────────────────────────────  ─────────────────  ──────────
--     demo.admin@madrassa360.pk          Admin (owner)      Demo@1234
--     demo.principal@madrassa360.pk      Principal          Demo@1234
--     demo.teacher@madrassa360.pk        Teacher            Demo@1234
--     demo.accountant@madrassa360.pk     Accountant         Demo@1234
--     demo.parent@madrassa360.pk         Parent             Demo@1234
--
--   The same Supabase backend serves the SaaS/web dashboard AND the Flutter
--   app, so these logins work in both.
--
-- ═══ HOW TO RUN ═══
--   Supabase Dashboard → SQL Editor → New query → paste this whole file →
--   Run. Idempotent: safe to re-run (ON CONFLICT DO NOTHING everywhere).
--   If a demo user does not exist yet, its linked rows are skipped with a
--   NOTICE — create the user and re-run the script.
--
--   Do NOT run on a production database holding real data unless you
--   intend to add a demo tenant there.
-- ═══════════════════════════════════════════════════════════════════

-- ─────────────────── PART A: tenant & business data ───────────────────

INSERT INTO public.tenants
  (id, tenant_code, name, name_urdu, slug, address, city, district, province,
   country, phone, email, website, principal_name, registration_number, status)
VALUES
  ('c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'DEMO-360', 'Demo Madrassa', 'ڈیمو مدرسہ', 'demo-madrassa',
   'مین بازار، شاہدرہ', 'لاہور', 'لاہور', 'پنجاب', 'Pakistan',
   '0300-1234567', 'info@demo-madrassa.pk', 'https://demo-madrassa.pk',
   'مولانا عبدالرحمن', 'REG-DEMO-2026-001', 'active')
ON CONFLICT (id) DO NOTHING;

UPDATE public.tenant_settings
   SET language = 'ur', timezone = 'Asia/Karachi', currency = 'PKR',
       academic_year = '2026-27', font = 'JameelNooriNastaleeq',
       receipt_header = 'ڈیمو مدرسہ — لاہور',
       receipt_footer = 'شکریہ! براہ کرم رسید سنبھال کر رکھیں۔'
 WHERE tenant_id = 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924';

INSERT INTO public.tenant_modules (tenant_id, module, enabled) VALUES
  ('c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'finance', true),
  ('c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'staff',   true),
  ('c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'library', true)
ON CONFLICT (tenant_id, module) DO NOTHING;

SELECT public.provision_role_templates('c54de9d9-eaf4-4f4f-bed5-a3f05acd9924'::uuid);


-- Darjas (درجات).
INSERT INTO public.darjas (id, tenant_id, name, name_en, order_num, is_active) VALUES
  ('5499008e-18d6-400d-8903-e88c91840b2a', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'ناظرہ قرآن', 'Nazra Quran', 1, true),
  ('217fa880-fe41-4d7e-b44e-226c800eca6e', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'حفظ قرآن', 'Hifz-e-Quran', 2, true),
  ('3db1694c-6fd4-4b45-991a-9233b7c121e1', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'درجہ اول', 'Grade 1', 3, true),
  ('d2ea0c57-6b91-4cf2-ac2c-dfc48515ff7e', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'درجہ دوم', 'Grade 2', 4, true),
  ('77cafc64-65c3-40a4-b727-d9d5c13a2ab0', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'درجہ سوم', 'Grade 3', 5, true),
  ('28667aa4-a199-41c9-a804-428848d35c9a', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'درجہ چہارم', 'Grade 4', 6, true)
ON CONFLICT (id) DO NOTHING;

-- Classes (جماعتیں). teacher_id linked in PART B.
INSERT INTO public.classes (id, tenant_id, darja_id, name, capacity, is_active) VALUES
  ('3600b296-ae6f-4ae9-842e-7f41e0c5d76a', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '5499008e-18d6-400d-8903-e88c91840b2a', 'جماعت الف — ناظرہ', 40, true),
  ('011573fd-6780-4ed2-9057-8ad4fa6e20ed', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '5499008e-18d6-400d-8903-e88c91840b2a', 'جماعت ب — ناظرہ', 40, true),
  ('99eab3ee-2045-4865-88fb-5f92c289e92e', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '217fa880-fe41-4d7e-b44e-226c800eca6e', 'جماعت الف — حفظ', 40, true),
  ('15c5da51-352a-46d0-b171-1d9677400b0a', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '217fa880-fe41-4d7e-b44e-226c800eca6e', 'جماعت ب — حفظ', 40, true),
  ('8a706666-5629-439b-806b-e3c13a1e9337', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '3db1694c-6fd4-4b45-991a-9233b7c121e1', 'جماعت الف — درجہ اول', 40, true),
  ('fc5a6d78-614b-4b76-a073-df5b61ef5624', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'd2ea0c57-6b91-4cf2-ac2c-dfc48515ff7e', 'جماعت الف — درجہ دوم', 40, true),
  ('ce0987ea-47df-4689-a53f-21ae578d3d1d', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '77cafc64-65c3-40a4-b727-d9d5c13a2ab0', 'جماعت الف — درجہ سوم', 40, true),
  ('8eec3e19-e664-4797-bc35-7f08e84ad123', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '28667aa4-a199-41c9-a804-428848d35c9a', 'جماعت الف — درجہ چہارم', 40, true)
ON CONFLICT (id) DO NOTHING;

-- Students (طلبہ) — 28 students.
INSERT INTO public.students (id, tenant_id, roll_no, name, father_name, darja_id, class_id, phone, address, date_of_admit, is_active) VALUES
  ('9bf2ea72-a633-4608-81df-46e4b8187f5f', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-001', 'محمد احمد', 'محمد اسلم', '5499008e-18d6-400d-8903-e88c91840b2a', '3600b296-ae6f-4ae9-842e-7f41e0c5d76a', '0301-1110001', 'شاہدرہ، لاہور', CURRENT_DATE - 180, true),
  ('fff2ae76-5347-431d-a587-c4dea9de5956', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-002', 'علی رضا', 'عبدالرحیم', '5499008e-18d6-400d-8903-e88c91840b2a', '3600b296-ae6f-4ae9-842e-7f41e0c5d76a', '0301-1110002', 'شاہدرہ، لاہور', CURRENT_DATE - 180, true),
  ('f4a82dfa-5e6d-4a66-b9ec-8f6a8f4c3082', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-003', 'حسن جاوید', 'محمد شریف', '5499008e-18d6-400d-8903-e88c91840b2a', '3600b296-ae6f-4ae9-842e-7f41e0c5d76a', '0301-1110003', 'بادامی باغ، لاہور', CURRENT_DATE - 180, true),
  ('f26333cc-cfff-43ed-b5ea-af14de18c443', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-004', 'عمر فاروق', 'غلام محمد', '5499008e-18d6-400d-8903-e88c91840b2a', '3600b296-ae6f-4ae9-842e-7f41e0c5d76a', '0301-1110004', 'راوی روڈ، لاہور', CURRENT_DATE - 180, true),
  ('1ef306bf-43db-4eff-8475-dfafe8a281ae', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-005', 'بلال احمد', 'اللہ دتہ', '5499008e-18d6-400d-8903-e88c91840b2a', '011573fd-6780-4ed2-9057-8ad4fa6e20ed', '0301-1110005', 'شاہدرہ، لاہور', CURRENT_DATE - 180, true),
  ('25b09983-f650-42c9-b495-56c56499fb9c', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-006', 'زید اکرم', 'محمد یوسف', '5499008e-18d6-400d-8903-e88c91840b2a', '011573fd-6780-4ed2-9057-8ad4fa6e20ed', '0301-1110006', 'سگیاں، لاہور', CURRENT_DATE - 180, true),
  ('e2ff00ab-fdd8-41ab-b115-7c894aa50916', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-007', 'حمزہ شاہد', 'عبدالکریم', '5499008e-18d6-400d-8903-e88c91840b2a', '011573fd-6780-4ed2-9057-8ad4fa6e20ed', '0301-1110007', 'بادامی باغ، لاہور', CURRENT_DATE - 180, true),
  ('dc42603f-d063-4cec-b6eb-a0d5fba2d6d9', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-008', 'طلحہ محمود', 'حاجی محمد دین', '5499008e-18d6-400d-8903-e88c91840b2a', '011573fd-6780-4ed2-9057-8ad4fa6e20ed', '0301-1110008', 'شاہدرہ، لاہور', CURRENT_DATE - 180, true),
  ('6670f2b3-4d43-42e3-b342-af65e0259e58', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-009', 'عبداللہ نعیم', 'محمد اکرم', '217fa880-fe41-4d7e-b44e-226c800eca6e', '99eab3ee-2045-4865-88fb-5f92c289e92e', '0301-1110009', 'قصبہ گجراں، لاہور', CURRENT_DATE - 180, true),
  ('91c418bb-c3ed-440a-80f3-58a39fd73801', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-010', 'ابوبکر صدیق', 'چوہدری انور علی', '217fa880-fe41-4d7e-b44e-226c800eca6e', '99eab3ee-2045-4865-88fb-5f92c289e92e', '0301-1110010', 'شاہدرہ، لاہور', CURRENT_DATE - 180, true),
  ('f8825377-60de-4f39-bddb-15c42af098f5', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-011', 'عثمان غنی', 'محمد صادق', '217fa880-fe41-4d7e-b44e-226c800eca6e', '99eab3ee-2045-4865-88fb-5f92c289e92e', '0301-1110011', 'بیگم کوٹ، لاہور', CURRENT_DATE - 180, true),
  ('9c3c685a-98ea-418f-bb19-edab66d8f504', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-012', 'سلمان راشد', 'عبدالغفار', '217fa880-fe41-4d7e-b44e-226c800eca6e', '99eab3ee-2045-4865-88fb-5f92c289e92e', '0301-1110012', 'شاہدرہ، لاہور', CURRENT_DATE - 180, true),
  ('6dc1f7c2-4ed3-466d-9e02-ab385bf30ba2', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-013', 'دانیال خالد', 'محمد خالد', '217fa880-fe41-4d7e-b44e-226c800eca6e', '15c5da51-352a-46d0-b171-1d9677400b0a', '0301-1110013', 'کوٹ عبدالمالک', CURRENT_DATE - 180, true),
  ('ba33c832-c912-47e1-993d-983a82709ec0', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-014', 'عمران سعید', 'سعید احمد', '217fa880-fe41-4d7e-b44e-226c800eca6e', '15c5da51-352a-46d0-b171-1d9677400b0a', '0301-1110014', 'شاہدرہ، لاہور', CURRENT_DATE - 180, true),
  ('6ccf1c2d-9c40-4676-a523-5eb9f4327ff2', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-015', 'وقاص یونس', 'محمد یونس', '217fa880-fe41-4d7e-b44e-226c800eca6e', '15c5da51-352a-46d0-b171-1d9677400b0a', '0301-1110015', 'فیروز والا', CURRENT_DATE - 180, true),
  ('bea6d014-4965-4439-bc6f-7885092256f7', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-016', 'یوسف فاروقی', 'مفتی عبدالقیوم', '3db1694c-6fd4-4b45-991a-9233b7c121e1', '8a706666-5629-439b-806b-e3c13a1e9337', '0301-1110016', 'شاہدرہ، لاہور', CURRENT_DATE - 180, true),
  ('a344eb0b-aa30-4b67-81c2-171ff9cecf95', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-017', 'ابراہیم خان', 'شیر خان', '3db1694c-6fd4-4b45-991a-9233b7c121e1', '8a706666-5629-439b-806b-e3c13a1e9337', '0301-1110017', 'بادامی باغ، لاہور', CURRENT_DATE - 180, true),
  ('b31d4644-8fde-42b1-a000-d3352bbad95d', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-018', 'اسماعیل احمد', 'احمد دین', '3db1694c-6fd4-4b45-991a-9233b7c121e1', '8a706666-5629-439b-806b-e3c13a1e9337', '0301-1110018', 'راوی روڈ، لاہور', CURRENT_DATE - 180, true),
  ('725c81ce-c67f-4e56-9ab6-f099d5a821b4', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-019', 'اسحاق محمد', 'محمد اسحاق', '3db1694c-6fd4-4b45-991a-9233b7c121e1', '8a706666-5629-439b-806b-e3c13a1e9337', '0301-1110019', 'شاہدرہ، لاہور', CURRENT_DATE - 180, true),
  ('36f0b3f1-f8ec-4263-88d0-a67b2f8da52d', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-020', 'موسیٰ رضا', 'رضا محمد', 'd2ea0c57-6b91-4cf2-ac2c-dfc48515ff7e', 'fc5a6d78-614b-4b76-a073-df5b61ef5624', '0301-1110020', 'سگیاں، لاہور', CURRENT_DATE - 180, true),
  ('fe211b8d-4aa2-474b-9982-e79ecb6c06ed', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-021', 'ہارون رشید', 'رشید احمد', 'd2ea0c57-6b91-4cf2-ac2c-dfc48515ff7e', 'fc5a6d78-614b-4b76-a073-df5b61ef5624', '0301-1110021', 'شاہدرہ، لاہور', CURRENT_DATE - 180, true),
  ('498c735e-9009-4da9-b741-321ead8f60f3', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-022', 'سلیمان ناصر', 'ناصر محمود', 'd2ea0c57-6b91-4cf2-ac2c-dfc48515ff7e', 'fc5a6d78-614b-4b76-a073-df5b61ef5624', '0301-1110022', 'قصبہ گجراں، لاہور', CURRENT_DATE - 180, true),
  ('e89449f9-c24f-4c4b-8cd6-55636db6024b', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-023', 'داؤد انور', 'انور حسین', '77cafc64-65c3-40a4-b727-d9d5c13a2ab0', 'ce0987ea-47df-4689-a53f-21ae578d3d1d', '0301-1110023', 'شاہدرہ، لاہور', CURRENT_DATE - 180, true),
  ('547e390b-f78f-4acb-828a-63ee7f7d9d53', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-024', 'زکریا یوسف', 'یوسف علی', '77cafc64-65c3-40a4-b727-d9d5c13a2ab0', 'ce0987ea-47df-4689-a53f-21ae578d3d1d', '0301-1110024', 'بیگم کوٹ، لاہور', CURRENT_DATE - 180, true),
  ('09c6a130-e730-4cf9-ae6e-41a0f9acd532', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-025', 'یحییٰ کریم', 'کریم بخش', '77cafc64-65c3-40a4-b727-d9d5c13a2ab0', 'ce0987ea-47df-4689-a53f-21ae578d3d1d', '0301-1110025', 'شاہدرہ، لاہور', CURRENT_DATE - 180, true),
  ('a5bdca80-e290-4ef4-a210-48a89c85c290', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-026', 'عیسیٰ خان', 'خان محمد', '28667aa4-a199-41c9-a804-428848d35c9a', '8eec3e19-e664-4797-bc35-7f08e84ad123', '0301-1110026', 'فیروز والا', CURRENT_DATE - 180, true),
  ('2622e9ee-90ff-40d5-a033-d15dd09e3314', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-027', 'الیاس احمد', 'احمد خان', '28667aa4-a199-41c9-a804-428848d35c9a', '8eec3e19-e664-4797-bc35-7f08e84ad123', '0301-1110027', 'شاہدرہ، لاہور', CURRENT_DATE - 180, true),
  ('c1a19bc9-5924-48fd-8cd2-724d963cc3b8', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'D-2026-028', 'شعیب اختر', 'اختر علی', '28667aa4-a199-41c9-a804-428848d35c9a', '8eec3e19-e664-4797-bc35-7f08e84ad123', '0301-1110028', 'کوٹ عبدالمالک', CURRENT_DATE - 180, true)
ON CONFLICT (id) DO NOTHING;

-- Staff (عملہ).
INSERT INTO public.staff (id, tenant_id, name, father_name, designation, department, phone, salary, joining_date, is_active) VALUES
  ('e0fc3e99-0f3d-4cf6-a6b5-14ca0c2037de', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'محمد اکرم', 'اللہ رکھا', 'کلرک', 'انتظامیہ', '0321-2220001', 35000, '2024-04-01', true),
  ('6e67f506-a8f7-4c6c-8854-24b5838b72d1', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'شاہد محمود', 'محمود احمد', 'باورچی', 'مطبخ', '0321-2220002', 30000, '2024-06-15', true),
  ('79deafd9-9faa-4c19-a48c-e26c80584a77', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'ناصر علی', 'علی محمد', 'چوکیدار', 'حفاظت', '0321-2220003', 28000, '2025-01-10', true)
ON CONFLICT (id) DO NOTHING;

-- Monthly fees (legacy fees table) for the current month.
DO $$
DECLARE
  v_due   NUMERIC(10,2);
  v_paid  NUMERIC(10,2);
  v_mod   INT;
  v_idx   INT := 0;
  v_month TEXT := to_char(CURRENT_DATE, 'YYYY-MM');
  r RECORD;
BEGIN
  FOR r IN SELECT s.id, d.order_num
             FROM public.students s
             JOIN public.darjas d ON d.id = s.darja_id
            WHERE s.tenant_id = 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924' AND s.is_active
            ORDER BY s.roll_no
  LOOP
    v_idx := v_idx + 1;
    v_due := CASE WHEN r.order_num = 1 THEN 500
                  WHEN r.order_num = 2 THEN 800
                  ELSE 1000 END;
    v_mod := v_idx % 10;
    v_paid := CASE WHEN v_mod <= 6 THEN v_due
                   WHEN v_mod <= 8 THEN v_due / 2
                   ELSE 0 END;
    INSERT INTO public.fees
      (tenant_id, student_id, month, amount_due, amount_paid, due_date, paid_date)
    VALUES
      ('c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', r.id, v_month, v_due, v_paid,
       date_trunc('month', CURRENT_DATE)::date + INTERVAL '10 days',
       CASE WHEN v_paid > 0 THEN CURRENT_DATE - (v_idx % 7) ELSE NULL END)
    ON CONFLICT (student_id, month) DO NOTHING;
  END LOOP;
END $$;


-- Exams (امتحانات).
INSERT INTO public.exams (id, tenant_id, name, class_id, exam_date, total_marks) VALUES
  ('01ec6fec-5173-4b15-b397-812e1b988ac7', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'امتحانِ ششماہی — ناظرہ', '3600b296-ae6f-4ae9-842e-7f41e0c5d76a', CURRENT_DATE - 20, 100),
  ('95fc1e99-77cb-4d5a-ab41-21a386408778', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'امتحانِ ششماہی — درجہ اول', '8a706666-5629-439b-806b-e3c13a1e9337', CURRENT_DATE - 20, 100)
ON CONFLICT (id) DO NOTHING;


-- Results (نتائج) — 4 subjects per student for both exams.
DO $$
DECLARE
  v_marks NUMERIC(6,2);
  v_si    INT;
  v_ji    INT;
  e RECORD;
  s RECORD;
BEGIN
  FOR e IN SELECT * FROM (VALUES
      ('01ec6fec-5173-4b15-b397-812e1b988ac7'::uuid, ARRAY['قرآن مجید','تجوید','اردو','اسلامیات']),
      ('95fc1e99-77cb-4d5a-ab41-21a386408778'::uuid, ARRAY['صرف','نحو','فقہ','اردو'])
    ) AS t(exam_id, subjects)
  LOOP
    v_si := 0;
    FOR s IN SELECT st.id FROM public.students st
              JOIN public.exams ex ON ex.id = e.exam_id
             WHERE st.class_id = ex.class_id AND st.tenant_id = 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924'
             ORDER BY st.roll_no
    LOOP
      v_si := v_si + 1;
      FOR v_ji IN 1..array_length(e.subjects, 1) LOOP
        v_marks := 55 + ((v_si * 11 + v_ji * 13) % 46);
        INSERT INTO public.results
          (tenant_id, exam_id, student_id, subject, marks_obtained, total_marks)
        VALUES
          ('c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', e.exam_id, s.id, e.subjects[v_ji], v_marks, 100)
        ON CONFLICT (exam_id, student_id, subject) DO NOTHING;
      END LOOP;
    END LOOP;
  END LOOP;
END $$;


-- Announcements (اعلانات). posted_by linked in PART B.
INSERT INTO public.announcements (id, tenant_id, title, body, target_role, is_active) VALUES
  ('9f72be8f-d643-4482-9d6f-b9ad26618d9e', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'داخلے جاری ہیں',
   'نئے تعلیمی سال کے داخلے جاری ہیں۔ خواہشمند والدین دفتر سے رابطہ کریں۔', 'all', true),
  ('664c8428-9612-4eb3-a950-2762720b62ca', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'والدین اساتذہ میٹنگ',
   'ماہانہ والدین اساتذہ میٹنگ بروز ہفتہ صبح 10 بجے ہوگی۔', 'parent', true),
  ('3add4ea4-6049-43a0-8cf4-5057bbd9ede1', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'ماہانہ فیس کی آخری تاریخ',
   'اس ماہ کی فیس جمع کروانے کی آخری تاریخ 10 تاریخ ہے۔', 'all', true),
  ('b61f464a-8c87-4d9b-9236-26ace36d4eed', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'امتحانی شیڈول',
   'ششماہی امتحانات کا شیڈول نوٹس بورڈ پر لگا دیا گیا ہے۔', 'teacher', true)
ON CONFLICT (id) DO NOTHING;


-- Chart of accounts (حسابات).
INSERT INTO public.accounts (id, tenant_id, code, name, name_urdu, account_type, opening_balance, is_active) VALUES
  ('85984c22-90c4-406c-9ae2-5e508d9fbf6a', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '1001', 'Cash in Hand', 'نقد', 'asset', 150000, true),
  ('25621ec4-6854-4079-b558-229725f0351d', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '1002', 'Bank Account', 'بینک', 'asset', 500000, true),
  ('05a34308-932e-4ff6-94ea-688c4fd618f4', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '4001', 'Fee Income', 'فیس آمدنی', 'income', 0, true),
  ('9f678e66-a3b3-4004-b694-6ab5933a1a8f', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '5001', 'Salary Expense', 'تنخواہ اخراجات', 'expense', 0, true)
ON CONFLICT (id) DO NOTHING;

-- Fee structures + items.
INSERT INTO public.fee_structures (id, tenant_id, name, name_urdu, darja_id, academic_year, is_active) VALUES
  ('1cbaae91-7796-43b3-848e-ce653beea5a0', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'Monthly Fee - Nazra', 'ماہانہ فیس — ناظرہ', '5499008e-18d6-400d-8903-e88c91840b2a', '2026-27', true),
  ('bf1f1f63-55f6-4dd0-aaf3-5e0628485b88', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'Monthly Fee - Darjat', 'ماہانہ فیس — درجات', '3db1694c-6fd4-4b45-991a-9233b7c121e1', '2026-27', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.fee_items (id, tenant_id, fee_structure_id, name, name_urdu, amount, frequency, is_active) VALUES
  ('b6e8a2c9-5010-4a8f-992c-549b435c8c76', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '1cbaae91-7796-43b3-848e-ce653beea5a0', 'Tuition Fee', 'ٹیوشن فیس', 500, 'monthly', true),
  ('7491ff1f-db18-4d5e-b541-d413d146c45a', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '1cbaae91-7796-43b3-848e-ce653beea5a0', 'Exam Fee', 'امتحانی فیس', 300, 'one_time', true),
  ('c8ab79c2-a20a-467f-aaa9-06a91c852861', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'bf1f1f63-55f6-4dd0-aaf3-5e0628485b88', 'Tuition Fee', 'ٹیوشن فیس', 1000, 'monthly', true),
  ('db423c1e-d7e5-42b1-8553-f00409bc89d7', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'bf1f1f63-55f6-4dd0-aaf3-5e0628485b88', 'Admission Fee', 'داخلہ فیس', 2000, 'one_time', true),
  ('8fa63f04-bbda-4736-9db4-cda6638602cc', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'bf1f1f63-55f6-4dd0-aaf3-5e0628485b88', 'Exam Fee', 'امتحانی فیس', 500, 'one_time', true),
  ('6d7307e1-7fae-44b9-8e5b-36c15850da32', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'bf1f1f63-55f6-4dd0-aaf3-5e0628485b88', 'Library Fee', 'لائبریری فیس', 200, 'annual', true)
ON CONFLICT (id) DO NOTHING;


-- Invoices (انوائسز) for 10 students + line items.
INSERT INTO public.invoices (id, tenant_id, student_id, fee_structure_id, billing_month, issue_date, due_date, subtotal, status) VALUES
  ('411d66a8-bb5c-4ee8-9642-ab351d137159', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '9bf2ea72-a633-4608-81df-46e4b8187f5f', '1cbaae91-7796-43b3-848e-ce653beea5a0', to_char(CURRENT_DATE,'YYYY-MM'), CURRENT_DATE - 5, CURRENT_DATE + 10, 500, 'issued'),
  ('dc210b95-6959-4c7b-91b6-996a4bff5057', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'fff2ae76-5347-431d-a587-c4dea9de5956', '1cbaae91-7796-43b3-848e-ce653beea5a0', to_char(CURRENT_DATE,'YYYY-MM'), CURRENT_DATE - 5, CURRENT_DATE + 10, 500, 'issued'),
  ('1011b44c-a6e5-4223-8021-762617e9e56b', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'f4a82dfa-5e6d-4a66-b9ec-8f6a8f4c3082', '1cbaae91-7796-43b3-848e-ce653beea5a0', to_char(CURRENT_DATE,'YYYY-MM'), CURRENT_DATE - 5, CURRENT_DATE + 10, 500, 'issued'),
  ('cb261f1d-77a4-4648-944f-63b4fd43f0ac', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'f26333cc-cfff-43ed-b5ea-af14de18c443', '1cbaae91-7796-43b3-848e-ce653beea5a0', to_char(CURRENT_DATE,'YYYY-MM'), CURRENT_DATE - 5, CURRENT_DATE + 10, 500, 'issued'),
  ('36c12081-923d-4694-8eb0-d07485876f90', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '1ef306bf-43db-4eff-8475-dfafe8a281ae', '1cbaae91-7796-43b3-848e-ce653beea5a0', to_char(CURRENT_DATE,'YYYY-MM'), CURRENT_DATE - 5, CURRENT_DATE + 10, 500, 'issued'),
  ('23dee24d-93d7-47b6-8ee3-fd074cc38b7e', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '25b09983-f650-42c9-b495-56c56499fb9c', '1cbaae91-7796-43b3-848e-ce653beea5a0', to_char(CURRENT_DATE,'YYYY-MM'), CURRENT_DATE - 5, CURRENT_DATE + 10, 500, 'issued'),
  ('7fa8bcb3-559f-4a84-b383-d4b9993048c8', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'e2ff00ab-fdd8-41ab-b115-7c894aa50916', '1cbaae91-7796-43b3-848e-ce653beea5a0', to_char(CURRENT_DATE,'YYYY-MM'), CURRENT_DATE - 5, CURRENT_DATE + 10, 500, 'issued'),
  ('e000b28f-d868-4f80-bfe2-68ef7d5d51ea', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'dc42603f-d063-4cec-b6eb-a0d5fba2d6d9', '1cbaae91-7796-43b3-848e-ce653beea5a0', to_char(CURRENT_DATE,'YYYY-MM'), CURRENT_DATE - 5, CURRENT_DATE + 10, 500, 'issued'),
  ('550ad3bd-1abc-42a2-86e8-6005cbd5dc40', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '6670f2b3-4d43-42e3-b342-af65e0259e58', 'bf1f1f63-55f6-4dd0-aaf3-5e0628485b88', to_char(CURRENT_DATE,'YYYY-MM'), CURRENT_DATE - 5, CURRENT_DATE + 10, 1000, 'issued'),
  ('2a6f987d-b113-40c0-a83b-b4bc8c3f588f', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '91c418bb-c3ed-440a-80f3-58a39fd73801', 'bf1f1f63-55f6-4dd0-aaf3-5e0628485b88', to_char(CURRENT_DATE,'YYYY-MM'), CURRENT_DATE - 5, CURRENT_DATE + 10, 1000, 'issued')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.invoice_items (id, tenant_id, invoice_id, fee_item_id, description, quantity, unit_amount) VALUES
  ('1012036d-b8f2-455d-8f14-1fda69b2b1fd', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '411d66a8-bb5c-4ee8-9642-ab351d137159', 'b6e8a2c9-5010-4a8f-992c-549b435c8c76', 'ٹیوشن فیس', 1, 500),
  ('bc0128d0-b205-422e-bd6d-fffe74f8af37', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'dc210b95-6959-4c7b-91b6-996a4bff5057', 'b6e8a2c9-5010-4a8f-992c-549b435c8c76', 'ٹیوشن فیس', 1, 500),
  ('953cd286-7367-4344-9049-cf5306f8e68a', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '1011b44c-a6e5-4223-8021-762617e9e56b', 'b6e8a2c9-5010-4a8f-992c-549b435c8c76', 'ٹیوشن فیس', 1, 500),
  ('d137ca91-77d2-4f9b-b346-b4c75e8830f0', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'cb261f1d-77a4-4648-944f-63b4fd43f0ac', 'b6e8a2c9-5010-4a8f-992c-549b435c8c76', 'ٹیوشن فیس', 1, 500),
  ('cfb88e15-35f1-4661-972d-3f25b7ee7bfa', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '36c12081-923d-4694-8eb0-d07485876f90', 'b6e8a2c9-5010-4a8f-992c-549b435c8c76', 'ٹیوشن فیس', 1, 500),
  ('44e3fad2-522e-456d-85cf-f96caa9169a3', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '23dee24d-93d7-47b6-8ee3-fd074cc38b7e', 'b6e8a2c9-5010-4a8f-992c-549b435c8c76', 'ٹیوشن فیس', 1, 500),
  ('c697809f-02d1-4cdd-ae21-a5cf76681c7e', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '7fa8bcb3-559f-4a84-b383-d4b9993048c8', 'b6e8a2c9-5010-4a8f-992c-549b435c8c76', 'ٹیوشن فیس', 1, 500),
  ('b5aed50b-dbdf-4fa8-ae8a-593a72f6db45', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'e000b28f-d868-4f80-bfe2-68ef7d5d51ea', 'b6e8a2c9-5010-4a8f-992c-549b435c8c76', 'ٹیوشن فیس', 1, 500),
  ('f3552c41-8983-43a6-ae32-41cb1f6762cf', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '550ad3bd-1abc-42a2-86e8-6005cbd5dc40', 'c8ab79c2-a20a-467f-aaa9-06a91c852861', 'ٹیوشن فیس', 1, 1000),
  ('78088d57-a932-4c51-a45f-6b90d505b3a7', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '2a6f987d-b113-40c0-a83b-b4bc8c3f588f', 'c8ab79c2-a20a-467f-aaa9-06a91c852861', 'ٹیوشن فیس', 1, 1000)
ON CONFLICT (id) DO NOTHING;

-- Payments (ادائیگیاں): 7 of 10 invoices paid in full, mixed methods.
-- Inserted as draft, then posted so triggers create ledger + allocations.

INSERT INTO public.payments (id, tenant_id, student_id, invoice_id, account_id, amount, payment_date, method, receipt_number, status) VALUES
  ('5cf237ea-e0d7-4f99-a1a5-eb7cce0ec25b', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '9bf2ea72-a633-4608-81df-46e4b8187f5f', '411d66a8-bb5c-4ee8-9642-ab351d137159', '85984c22-90c4-406c-9ae2-5e508d9fbf6a', 500, CURRENT_DATE - 2, 'cash', 'R-DEMO-001', 'draft'),
  ('3a4236fa-4dd3-410e-b4ce-32314f4f488c', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'fff2ae76-5347-431d-a587-c4dea9de5956', 'dc210b95-6959-4c7b-91b6-996a4bff5057', '85984c22-90c4-406c-9ae2-5e508d9fbf6a', 500, CURRENT_DATE - 2, 'jazzcash', 'R-DEMO-002', 'draft'),
  ('9b2e8089-2eb4-4e93-b59f-c31aebff805f', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'f4a82dfa-5e6d-4a66-b9ec-8f6a8f4c3082', '1011b44c-a6e5-4223-8021-762617e9e56b', '85984c22-90c4-406c-9ae2-5e508d9fbf6a', 500, CURRENT_DATE - 2, 'easypaisa', 'R-DEMO-003', 'draft'),
  ('470e0006-939a-4f7a-a424-9ec13c0942a3', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'f26333cc-cfff-43ed-b5ea-af14de18c443', 'cb261f1d-77a4-4648-944f-63b4fd43f0ac', '85984c22-90c4-406c-9ae2-5e508d9fbf6a', 500, CURRENT_DATE - 2, 'bank_transfer', 'R-DEMO-004', 'draft'),
  ('c30a0722-a881-44a2-80a0-7ae9e82c44ba', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '1ef306bf-43db-4eff-8475-dfafe8a281ae', '36c12081-923d-4694-8eb0-d07485876f90', '85984c22-90c4-406c-9ae2-5e508d9fbf6a', 500, CURRENT_DATE - 2, 'cash', 'R-DEMO-005', 'draft'),
  ('9edcbe0b-687e-416c-af90-3f2cd5643928', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '25b09983-f650-42c9-b495-56c56499fb9c', '23dee24d-93d7-47b6-8ee3-fd074cc38b7e', '85984c22-90c4-406c-9ae2-5e508d9fbf6a', 500, CURRENT_DATE - 2, 'jazzcash', 'R-DEMO-006', 'draft'),
  ('d8fa02d3-34e3-4836-991a-ffeeafe85af8', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'e2ff00ab-fdd8-41ab-b115-7c894aa50916', '7fa8bcb3-559f-4a84-b383-d4b9993048c8', '85984c22-90c4-406c-9ae2-5e508d9fbf6a', 500, CURRENT_DATE - 2, 'cash', 'R-DEMO-007', 'draft')
ON CONFLICT (id) DO NOTHING;
UPDATE public.payments SET status = 'posted'
 WHERE status = 'draft'
   AND id IN ('5cf237ea-e0d7-4f99-a1a5-eb7cce0ec25b', '3a4236fa-4dd3-410e-b4ce-32314f4f488c', '9b2e8089-2eb4-4e93-b59f-c31aebff805f', '470e0006-939a-4f7a-a424-9ec13c0942a3', 'c30a0722-a881-44a2-80a0-7ae9e82c44ba', '9edcbe0b-687e-416c-af90-3f2cd5643928', 'd8fa02d3-34e3-4836-991a-ffeeafe85af8');

-- One applied discount + one scholarship.
INSERT INTO public.discounts (id, tenant_id, student_id, invoice_id, discount_type, value, status) VALUES
  ('a349f566-8cb1-4bd2-bdeb-3eab6b23f808', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'dc42603f-d063-4cec-b6eb-a0d5fba2d6d9', 'e000b28f-d868-4f80-bfe2-68ef7d5d51ea', 'fixed', 200, 'draft')
ON CONFLICT (id) DO NOTHING;
UPDATE public.discounts SET status = 'applied' WHERE id = 'a349f566-8cb1-4bd2-bdeb-3eab6b23f808' AND status = 'draft';

INSERT INTO public.scholarships (id, tenant_id, student_id, name, discount_percent, start_date, status) VALUES
  ('c2cd93e0-82dd-4c48-aeb3-8a15345cfa32', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', '6670f2b3-4d43-42e3-b342-af65e0259e58', 'مستحق طلبہ اسکالرشپ', 50, CURRENT_DATE - 60, 'active')
ON CONFLICT (id) DO NOTHING;

-- Expenses & income (draft → posted so ledger entries are created).
INSERT INTO public.expenses (id, tenant_id, category, recipient, amount, account_id, expense_date, description, status) VALUES
  ('d20f51b5-67e2-4df1-bf81-4bd527d6e20e', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'تنخواہ', 'عملہ', 93000, '85984c22-90c4-406c-9ae2-5e508d9fbf6a', CURRENT_DATE - 8, 'ماہانہ تنخواہیں — عملہ', 'draft'),
  ('a6b49357-86e7-4a3c-a67e-b9ca71710b6f', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'بجلی', 'لیسکو', 12500, '25621ec4-6854-4079-b558-229725f0351d', CURRENT_DATE - 3, 'بجلی کا بل', 'draft')
ON CONFLICT (id) DO NOTHING;
UPDATE public.expenses SET status = 'posted' WHERE status = 'draft' AND id IN ('d20f51b5-67e2-4df1-bf81-4bd527d6e20e', 'a6b49357-86e7-4a3c-a67e-b9ca71710b6f');

INSERT INTO public.income (id, tenant_id, source_type, donor_name, amount, account_id, received_date, receipt_number, description, status) VALUES
  ('33917e63-d950-4564-ab3b-c02dc5586ba1', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'donation', 'حاجی محمد دین', 100000, '25621ec4-6854-4079-b558-229725f0351d', CURRENT_DATE - 12, 'DN-DEMO-001', 'عطیہ — تعمیر فنڈ', 'draft'),
  ('65ae7555-38bb-4147-813d-c79612d93117', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'zakat', 'اللہ رکھا', 50000, '85984c22-90c4-406c-9ae2-5e508d9fbf6a', CURRENT_DATE - 6, 'DN-DEMO-002', 'زکٰوۃ — مستحق طلبہ', 'draft')
ON CONFLICT (id) DO NOTHING;
UPDATE public.income SET status = 'posted' WHERE status = 'draft' AND id IN ('33917e63-d950-4564-ab3b-c02dc5586ba1', '65ae7555-38bb-4147-813d-c79612d93117');

-- Notifications (tenant-wide).
INSERT INTO public.notifications (id, tenant_id, type, title, title_urdu, body, body_urdu, channel) VALUES
  ('b65a4539-c924-4f9c-b25a-66397d7ad3c0', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'fee_reminder', 'Fee Reminder', 'فیس یاددہانی',
   'Monthly fee due date is approaching.', 'ماہانہ فیس کی آخری تاریخ قریب ہے۔', 'in_app'),
  ('85d00414-7a25-4e65-a872-c220053ae8a5', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'announcement', 'New Announcement', 'نیا اعلان',
   'Admissions are open for the new academic year.', 'نئے تعلیمی سال کے داخلے جاری ہیں۔', 'in_app'),
  ('7ffa3333-d4c2-489b-8792-230cea2a5701', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'exam', 'Exam Schedule', 'امتحانی شیڈول',
   'The six-monthly exam schedule has been published.', 'ششماہی امتحانات کا شیڈول جاری کر دیا گیا ہے۔', 'in_app')
ON CONFLICT (id) DO NOTHING;

-- Audit trail entries for the seed itself.
INSERT INTO public.audit_logs (id, tenant_id, action, entity, entity_id, new_data) VALUES
  ('3e28f8b1-1e76-4a17-a4f0-7f95c8b357e4', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'demo.seed', 'tenant', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924',
   '{"slug": "demo-madrassa", "students": 28, "classes": 8}'),
  ('32a5ac93-03b0-4b9d-8b97-fc86e3eafd0b', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', 'demo.seed.finance', 'tenant', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924',
   '{"invoices": 10, "payments_posted": 7}')
ON CONFLICT (id) DO NOTHING;

-- License: Professional plan, active for 1 year.
INSERT INTO public.licenses (id, tenant_id, plan_id, status, max_users, max_students, enabled_modules, expires_at)
SELECT '626fa77e-f165-453b-baec-0014a0cfa665', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', p.id, 'active', 50, 1000, p.enabled_modules, now() + INTERVAL '1 year'
  FROM public.license_plans p WHERE p.name = 'Professional'
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenant_subscriptions (id, tenant_id, plan_id, status, expires_at)
SELECT 'f0b036bc-a92d-41aa-abf6-859da8ccf03d', 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924', p.id, 'active', now() + INTERVAL '1 year'
  FROM public.license_plans p WHERE p.name = 'Professional'
ON CONFLICT (id) DO NOTHING;


-- ─────────────────── PART B: user-linked rows ───────────────────
-- Requires the 5 demo auth users (see header). Missing users → NOTICE, skip.
DO $$
DECLARE
  v_tenant    UUID := 'c54de9d9-eaf4-4f4f-bed5-a3f05acd9924';
  v_admin     UUID; v_principal UUID; v_teacher UUID; v_accountant UUID; v_parent UUID;
  v_date      DATE;
  v_back      INT := 0;
  v_taken     INT := 0;
  v_idx       INT;
  v_mod       INT;
  v_status    TEXT;
  r RECORD;
BEGIN

  SELECT id INTO v_admin FROM auth.users WHERE email = 'demo.admin@madrassa360.pk';
  IF v_admin IS NULL THEN
    RAISE NOTICE 'demo seed: auth user demo.admin@madrassa360.pk not found — skipping its links';
  ELSE
    INSERT INTO public.profiles (id, name, phone, role)
    VALUES (v_admin, 'ایڈمن (ڈیمو)', '0300-0000001', 'student')
    ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;
    INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active)
    VALUES (v_tenant, v_admin, 'tenant_owner', true)
    ON CONFLICT (user_id, tenant_id)
    DO UPDATE SET role = EXCLUDED.role, is_active = true;
  END IF;

  SELECT id INTO v_principal FROM auth.users WHERE email = 'demo.principal@madrassa360.pk';
  IF v_principal IS NULL THEN
    RAISE NOTICE 'demo seed: auth user demo.principal@madrassa360.pk not found — skipping its links';
  ELSE
    INSERT INTO public.profiles (id, name, phone, role)
    VALUES (v_principal, 'مولانا عبدالرحمن', '0300-0000002', 'student')
    ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;
    INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active)
    VALUES (v_tenant, v_principal, 'principal', true)
    ON CONFLICT (user_id, tenant_id)
    DO UPDATE SET role = EXCLUDED.role, is_active = true;
  END IF;

  SELECT id INTO v_teacher FROM auth.users WHERE email = 'demo.teacher@madrassa360.pk';
  IF v_teacher IS NULL THEN
    RAISE NOTICE 'demo seed: auth user demo.teacher@madrassa360.pk not found — skipping its links';
  ELSE
    INSERT INTO public.profiles (id, name, phone, role)
    VALUES (v_teacher, 'قاری محمد سلیم', '0300-0000003', 'student')
    ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;
    INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active)
    VALUES (v_tenant, v_teacher, 'teacher', true)
    ON CONFLICT (user_id, tenant_id)
    DO UPDATE SET role = EXCLUDED.role, is_active = true;
  END IF;

  SELECT id INTO v_accountant FROM auth.users WHERE email = 'demo.accountant@madrassa360.pk';
  IF v_accountant IS NULL THEN
    RAISE NOTICE 'demo seed: auth user demo.accountant@madrassa360.pk not found — skipping its links';
  ELSE
    INSERT INTO public.profiles (id, name, phone, role)
    VALUES (v_accountant, 'محمد نواز', '0300-0000004', 'student')
    ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;
    INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active)
    VALUES (v_tenant, v_accountant, 'accountant', true)
    ON CONFLICT (user_id, tenant_id)
    DO UPDATE SET role = EXCLUDED.role, is_active = true;
  END IF;

  SELECT id INTO v_parent FROM auth.users WHERE email = 'demo.parent@madrassa360.pk';
  IF v_parent IS NULL THEN
    RAISE NOTICE 'demo seed: auth user demo.parent@madrassa360.pk not found — skipping its links';
  ELSE
    INSERT INTO public.profiles (id, name, phone, role)
    VALUES (v_parent, 'محمد اسلم (والد)', '0301-1110001', 'student')
    ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;
    INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active)
    VALUES (v_tenant, v_parent, 'parent', true)
    ON CONFLICT (user_id, tenant_id)
    DO UPDATE SET role = EXCLUDED.role, is_active = true;
  END IF;


  -- Class teachers: demo teacher heads the two Nazra sections.
  IF v_teacher IS NOT NULL THEN
    UPDATE public.classes SET teacher_id = v_teacher
     WHERE id IN ('3600b296-ae6f-4ae9-842e-7f41e0c5d76a', '011573fd-6780-4ed2-9057-8ad4fa6e20ed') AND tenant_id = v_tenant;

    -- Teacher ↔ class assignments with subjects.
    INSERT INTO public.teacher_class_assignments
      (tenant_id, teacher_user_id, class_id, subject, academic_year, is_active) VALUES
      (v_tenant, v_teacher, '3600b296-ae6f-4ae9-842e-7f41e0c5d76a', 'قرآن مجید', '2026-27', true),
      (v_tenant, v_teacher, '011573fd-6780-4ed2-9057-8ad4fa6e20ed', 'تجوید', '2026-27', true),
      (v_tenant, v_teacher, '8a706666-5629-439b-806b-e3c13a1e9337', 'صرف', '2026-27', true)
    ON CONFLICT (tenant_id, teacher_user_id, class_id, subject) DO NOTHING;

    -- Attendance: last 5 teaching days (skips Friday), all students.
    WHILE v_taken < 5 LOOP
      v_date := CURRENT_DATE - v_back;
      v_back := v_back + 1;
      IF EXTRACT(DOW FROM v_date) = 5 THEN CONTINUE; END IF;  -- Friday off
      v_taken := v_taken + 1;
      v_idx := 0;
      FOR r IN SELECT s.id, s.class_id FROM public.students s
               WHERE s.tenant_id = v_tenant AND s.is_active ORDER BY s.roll_no
      LOOP
        v_idx := v_idx + 1;
        v_mod := (v_idx * 7 + v_taken) % 20;
        v_status := CASE WHEN v_mod = 0 THEN 'absent'
                         WHEN v_mod = 1 THEN 'leave'
                         ELSE 'present' END;
        INSERT INTO public.attendance
          (tenant_id, student_id, class_id, teacher_id, date, status)
        VALUES (v_tenant, r.id, r.class_id, v_teacher, v_date, v_status)
        ON CONFLICT (student_id, date) DO NOTHING;
      END LOOP;
    END LOOP;
  END IF;


  -- Parent links: demo parent is guardian of the first two students.
  IF v_parent IS NOT NULL THEN
    INSERT INTO public.student_guardians
      (tenant_id, student_id, guardian_user_id, relationship, is_primary)
    SELECT v_tenant, s.id, v_parent, 'father', (s.roll_no = 'D-2026-001')
      FROM public.students s
     WHERE s.tenant_id = v_tenant AND s.roll_no IN ('D-2026-001', 'D-2026-002')
    ON CONFLICT (tenant_id, student_id, guardian_user_id) DO NOTHING;

    UPDATE public.students SET parent_user_id = v_parent
     WHERE tenant_id = v_tenant AND roll_no IN ('D-2026-001', 'D-2026-002');
  END IF;

  -- Announcements posted by admin.
  IF v_admin IS NOT NULL THEN
    UPDATE public.announcements SET posted_by = v_admin
     WHERE tenant_id = v_tenant AND posted_by IS NULL;
  END IF;

  RAISE NOTICE 'demo seed complete for tenant demo-madrassa (%)', v_tenant;
END $$;


-- ─── Verification ───
SELECT 'tenants' AS t, count(*) AS n FROM public.tenants WHERE slug = 'demo-madrassa'
UNION ALL SELECT 'darjas', count(*) FROM public.darjas WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa')
UNION ALL SELECT 'classes', count(*) FROM public.classes WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa')
UNION ALL SELECT 'students', count(*) FROM public.students WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa')
UNION ALL SELECT 'attendance', count(*) FROM public.attendance WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa')
UNION ALL SELECT 'invoices', count(*) FROM public.invoices WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa')
UNION ALL SELECT 'payments', count(*) FROM public.payments WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa')
UNION ALL SELECT 'memberships', count(*) FROM public.tenant_memberships WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
