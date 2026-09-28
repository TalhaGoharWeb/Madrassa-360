/// ڈیش بورڈ رہنمائی — اردو ہدایات
/// Urdu "how to use" guide shown inside every role dashboard.
///
/// [DashboardGuideScreen] takes a [roleKey] (e.g. 'principal', 'teacher',
/// 'accountant') and renders a step-by-step Urdu explanation of that
/// dashboard: what each card and section does and how to use it.
/// [DashboardGuideButton] is the AppBar entry point used by every
/// dashboard (icon: ؟ — tooltip 'رہنمائی').

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';

/// One guide section: a heading plus bullet-point explanations.
class GuideSection {
  final IconData icon;
  final String heading;
  final List<String> points;

  const GuideSection({
    required this.icon,
    required this.heading,
    required this.points,
  });
}

/// Full guide content for one dashboard role.
class DashboardGuide {
  final String title;
  final String intro;
  final List<GuideSection> sections;

  const DashboardGuide({
    required this.title,
    required this.intro,
    required this.sections,
  });
}

const Map<String, DashboardGuide> dashboardGuides = {
  'principal': DashboardGuide(
    title: 'پرنسپل ڈیش بورڈ کی رہنمائی',
    intro: 'یہ ڈیش بورڈ مدرسے کے مجموعی انتظام کے لیے ہے۔ یہاں سے آپ '
        'طلبہ، اساتذہ، حاضری، فیس اور رپورٹس — سب کچھ ایک نظر میں دیکھ '
        'اور منظم کر سکتے ہیں۔',
    sections: [
      GuideSection(
        icon: Icons.dashboard_outlined,
        heading: 'مدرسے کا جائزہ',
        points: [
          'طلبہ: مدرسے میں داخل کل طلبہ کی تعداد۔',
          'اساتذہ: فعال اساتذہ کی تعداد۔',
          'آج حاضری: آج حاضر طلبہ کی تعداد — روزانہ یہاں سے حاضری کی صورتحال دیکھیں۔',
          'آج کی وصولی: آج وصول شدہ فیس کی رقم۔',
        ],
      ),
      GuideSection(
        icon: Icons.schedule_outlined,
        heading: 'آج کا شیڈول',
        points: [
          'دن کی ٹائم لائن میں آج کے اہم اوقات اور کام نظر آتے ہیں۔',
        ],
      ),
      GuideSection(
        icon: Icons.bolt_outlined,
        heading: 'فوری عمل',
        points: [
          'طالب علم داخل کریں: نیا داخلہ فارم کھولتا ہے۔',
          'استاد شامل کریں: نیا استاد یا عملہ شامل کریں۔',
          'حاضری: حاضری کی اسکرین کھولیں۔',
          'فیس وصول کریں: فیس وصولی کی اسکرین کھولیں۔',
          'اعلان کریں: تمام طلبہ و عملہ کے لیے نیا اعلان شائع کریں۔',
          'رپورٹ بنائیں: حاضری، نتائج اور مالی رپورٹس بنائیں۔',
          'امتحان بنائیں: مرحلہ وار امتحان بنانے کا وزڈ کھولیں۔',
        ],
      ),
      GuideSection(
        icon: Icons.category_outlined,
        heading: 'شعبہ جات',
        points: [
          'انتظامیہ: صارفین اور عملہ کا انتظام۔',
          'تعلیم: حاضری، درجات، طلبہ اور نتائج۔',
          'مالیات: فیس اور مالی حساب کتاب۔',
          'لائبریری: کتب خانہ کا ریکارڈ۔',
        ],
      ),
      GuideSection(
        icon: Icons.warning_amber_outlined,
        heading: 'اہم امور',
        points: [
          'یہاں وہ تنبیہات نظر آتی ہیں جن پر فوری توجہ درکار ہو، مثلاً بقایا فیس یا نامکمل کام۔',
        ],
      ),
    ],
  ),
  'teacher': DashboardGuide(
    title: 'استاد ڈیش بورڈ کی رہنمائی',
    intro: 'یہ آپ کا روزانہ کا تدریسی ڈیش بورڈ ہے۔ حاضری لگائیں، اپنے '
        'طلبہ دیکھیں اور نمبر درج کریں — سب کچھ یہیں سے۔',
    sections: [
      GuideSection(
        icon: Icons.dashboard_outlined,
        heading: 'خلاصہ کارڈز',
        points: [
          'میری جماعتیں: آپ کو سونپی گئی جماعتوں کی تعداد — دبانے پر جماعتوں کی فہرست کھلتی ہے۔',
          'میرے طلبہ: آپ کے زیرِ تعلیم طلبہ کی تعداد — دبانے پر طلبہ کی فہرست کھلتی ہے۔',
          'آج کی حاضری: آج کی حاضری کی صورتحال۔',
          'آج کے اسباق: آج کے درج شدہ اسباق۔',
        ],
      ),
      GuideSection(
        icon: Icons.bolt_outlined,
        heading: 'فوری عمل',
        points: [
          'حاضری لگائیں: آج کی حاضری درج کرنے کی اسکرین کھولیں۔',
          'طلبہ دیکھیں: اپنے طلبہ کی مکمل فہرست دیکھیں۔',
          'نمبر درج کریں: امتحانی نمبرات درج کرنے کی اسکرین کھولیں۔',
        ],
      ),
      GuideSection(
        icon: Icons.checklist_outlined,
        heading: 'آج کے کام',
        points: [
          'روزانہ کے کاموں کی فہرست یہاں نظر آتی ہے۔',
          'مکمل کام پر ٹک لگائیں — نشان باقی رہے گا۔',
        ],
      ),
      GuideSection(
        icon: Icons.campaign_outlined,
        heading: 'تازہ اعلانات',
        points: [
          'انتظامیہ کے تازہ اعلانات یہاں نظر آتے ہیں۔',
          'گھنٹی کے بٹن سے تمام اعلانات کی فہرست کھولیں۔',
        ],
      ),
      GuideSection(
        icon: Icons.tab_outlined,
        heading: 'نیچے والے ٹیبز',
        points: [
          'ڈیش بورڈ: یہی خلاصہ اسکرین۔',
          'میری جماعتیں اور میرے طلبہ: متعلقہ فہرستیں۔',
          'حاضری: روزانہ حاضری درج کریں۔',
          'امتحانات اور نتائج: امتحانی کام (اجازت کے مطابق)۔',
        ],
      ),
    ],
  ),
  'accountant': DashboardGuide(
    title: 'اکاؤنٹنٹ ڈیش بورڈ کی رہنمائی',
    intro: 'یہ ڈیش بورڈ مدرسے کے مالی حساب کتاب کے لیے ہے: فیس کی وصولی، '
        'اخراجات کا اندراج اور روزانہ کی مالی رپورٹ۔',
    sections: [
      GuideSection(
        icon: Icons.account_balance_wallet_outlined,
        heading: 'مالی خلاصہ',
        points: [
          'آج کی وصولی: آج وصول شدہ کل رقم۔',
          'بقایا فیس: طلبہ کے ذمے واجب الادا رقم۔',
          'آج کے اخراجات: آج درج شدہ اخراجات۔',
          'نقد رقم: موجودہ نقد بیلنس۔',
        ],
      ),
      GuideSection(
        icon: Icons.bolt_outlined,
        heading: 'فوری عمل',
        points: [
          'فیس وصول کریں: طالب علم کی فیس وصول کر کے رسید بنائیں۔',
          'رسید بنائیں: وصولی کی رسید تیار کریں۔',
          'خرچ درج کریں: نیا خرچ (مثلاً تنخواہ، یوٹیلٹی) درج کریں۔',
          'آمدن درج کریں: عطیہ یا دیگر آمدن درج کریں۔',
          'حساب دیکھیں اور تفصیلی حسابات: مکمل مالی ریکارڈ دیکھیں۔',
          'مالی رپورٹ: مدت کے حساب سے رپورٹ بنائیں۔',
        ],
      ),
      GuideSection(
        icon: Icons.checklist_outlined,
        heading: 'میرا آج کا کام',
        points: [
          'آج کی وصولی مکمل کریں: دن کے اختتام پر وصولی کا جائزہ لیں۔',
          'بقایا فیس کا جائزہ لیں: واجب الادا فیس والے طلبہ دیکھیں۔',
          'آج کے اخراجات درج کریں: کوئی خرچ رہ نہ جائے۔',
        ],
      ),
    ],
  ),
  'clerk': DashboardGuide(
    title: 'دفتری ڈیش بورڈ کی رہنمائی',
    intro: 'یہ ڈیش بورڈ داخلہ دفتر کے روزمرہ کام کے لیے ہے: نئے داخلے، '
        'فیس کی وصولی اور رسیدیں۔',
    sections: [
      GuideSection(
        icon: Icons.dashboard_outlined,
        heading: 'اعداد و شمار',
        points: [
          'نئے داخلے: حالیہ نئے داخلوں کی تعداد۔',
          'زیرِ تکمیل داخلے: جن داخلوں کا کام ابھی مکمل نہیں ہوا۔',
          'دستاویزات باقی: جن طلبہ کی دستاویزات جمع ہونا باقی ہیں۔',
          'آج کی فیس: آج وصول شدہ فیس۔',
        ],
      ),
      GuideSection(
        icon: Icons.bolt_outlined,
        heading: 'فوری عمل',
        points: [
          'نیا داخلہ: نئے طالب علم کا داخلہ فارم کھولیں۔',
          'طلبہ کی فہرست: تمام طلبہ کا ریکارڈ دیکھیں۔',
          'فیس وصول کریں: فیس وصولی کی اسکرین کھولیں۔',
          'رسید بنائیں: فیس کی رسید تیار کریں۔',
        ],
      ),
      GuideSection(
        icon: Icons.checklist_outlined,
        heading: 'آج کے کام',
        points: [
          'داخلے مکمل کریں: زیرِ تکمیل داخلوں کو مکمل کریں۔',
          'رسیدیں تیار کریں: باقی رسیدیں بنائیں۔',
        ],
      ),
    ],
  ),
  'academic_admin': DashboardGuide(
    title: 'تعلیمی ناظم ڈیش بورڈ کی رہنمائی',
    intro: 'یہ ڈیش بورڈ تعلیمی نظام کے انتظام کے لیے ہے: جماعتیں، اساتذہ، '
        'امتحانات اور نتائج۔',
    sections: [
      GuideSection(
        icon: Icons.dashboard_outlined,
        heading: 'تعلیمی خلاصہ',
        points: [
          'طلبہ اور اساتذہ: کل تعداد۔',
          'درجات: جماعتوں/درجوں کی تعداد۔',
          'آج حاضری: آج کی حاضری کی صورتحال۔',
        ],
      ),
      GuideSection(
        icon: Icons.bolt_outlined,
        heading: 'فوری عمل',
        points: [
          'استاد مقرر کریں: جماعت کے لیے استاد تفویض کریں۔',
          'جماعت بنائیں: نئی جماعت یا درجہ بنائیں۔',
          'امتحان بنائیں: مرحلہ وار امتحان وزڈ کھولیں۔',
          'نتائج دیکھیں: شائع شدہ نتائج ملاحظہ کریں۔',
        ],
      ),
      GuideSection(
        icon: Icons.pending_actions_outlined,
        heading: 'زیرِ تکمیل نتائج',
        points: [
          'جن امتحانات کے نتائج ابھی تیار یا شائع نہیں ہوئے، وہ یہاں نظر آتے ہیں۔',
        ],
      ),
    ],
  ),
  'hostel': DashboardGuide(
    title: 'دارالاقامہ ڈیش بورڈ کی رہنمائی',
    intro: 'یہ ڈیش بورڈ ہاسٹل (دارالاقامہ) کے رہائشی طلبہ کے انتظام کے لیے ہے۔',
    sections: [
      GuideSection(
        icon: Icons.dashboard_outlined,
        heading: 'رہائشی خلاصہ',
        points: [
          'رہائشی طلبہ: ہاسٹل میں مقیم کل طلبہ۔',
          'آج حاضر: آج حاضری میں موجود طلبہ۔',
          'غیر حاضر: آج غیر حاضر طلبہ۔',
          'چھٹی پر: چھٹی پر گئے طلبہ۔',
        ],
      ),
      GuideSection(
        icon: Icons.bolt_outlined,
        heading: 'فوری عمل',
        points: [
          'حاضری: رہائشی طلبہ کی روزانہ حاضری درج کریں۔',
          'رپورٹ: ہاسٹل کی حاضری رپورٹ دیکھیں۔',
        ],
      ),
    ],
  ),
  'librarian': DashboardGuide(
    title: 'کتب خانہ ڈیش بورڈ کی رہنمائی',
    intro: 'یہ ڈیش بورڈ لائبریری کے انتظام کے لیے ہے: کتابوں کا اجراء، '
        'واپسی اور تلاش۔',
    sections: [
      GuideSection(
        icon: Icons.dashboard_outlined,
        heading: 'کتب کا خلاصہ',
        points: [
          'کل کتب: لائبریری میں موجود کل کتابیں۔',
          'جاری شدہ: طلبہ کو دی گئی کتابیں۔',
          'واپسی باقی: جن کتابوں کی واپسی کی تاریخ گزر چکی یا قریب ہے۔',
        ],
      ),
      GuideSection(
        icon: Icons.bolt_outlined,
        heading: 'فوری عمل',
        points: [
          'کتاب جاری کریں: طالب علم کو کتاب دیں اور ریکارڈ درج کریں۔',
          'کتاب واپس لیں: واپس آنے والی کتاب کا اندراج کریں۔',
          'تلاش کریں: عنوان یا مصنف سے کتاب تلاش کریں۔',
          'کتب: مکمل کیٹلاگ دیکھیں۔',
          'رپورٹ: اجراء و واپسی کی رپورٹ دیکھیں۔',
        ],
      ),
    ],
  ),
  'exam': DashboardGuide(
    title: 'امتحانی ڈیش بورڈ کی رہنمائی',
    intro: 'یہ ڈیش بورڈ امتحانات کے مکمل انتظام کے لیے ہے: امتحان بنانے سے '
        'لیکر نتائج شائع کرنے تک۔',
    sections: [
      GuideSection(
        icon: Icons.dashboard_outlined,
        heading: 'امتحانی خلاصہ',
        points: [
          'جاری امتحانات: اس وقت جاری امتحانات کی تعداد۔',
          'نتائج تیار: جن کے نتائج تیار ہو چکے۔',
          'نتائج شائع شدہ: شائع شدہ نتائج۔',
          'نمبر درج ہونا باقی: جن میں نمبرات درج ہونا باقی ہیں۔',
        ],
      ),
      GuideSection(
        icon: Icons.bolt_outlined,
        heading: 'فوری عمل',
        points: [
          'امتحان بنائیں: 8 مرحلوں کا وزڈ کھولیں۔',
          'نمبر درج کریں: طلبہ کے نمبرات درج کریں۔',
          'نتائج دیکھیں: تیار نتائج ملاحظہ کریں۔',
          'رپورٹ: امتحانی رپورٹ دیکھیں۔',
        ],
      ),
      GuideSection(
        icon: Icons.list_alt_outlined,
        heading: 'امتحان بنانے کے مراحل',
        points: [
          '1۔ امتحان بنائیں: نام، جماعت اور تاریخ درج کریں۔',
          '2۔ مضامین: مضامین اور کل نمبر شامل کریں۔',
          '3۔ طلبہ: امتحان میں شامل طلبہ منتخب کریں۔',
          '4۔ نمبر درج کریں: ہر طالب علم کے نمبر لکھیں۔',
          '5۔ جانچ کریں: درج شدہ نمبرات کی تصدیق کریں۔',
          '6۔ نتیجہ تیار کریں: نتیجہ مرتب کریں۔',
          '7۔ منظوری: نتیجے کی منظوری دیں۔',
          '8۔ شائع کریں: نتیجہ شائع کریں۔',
        ],
      ),
    ],
  ),
  'admin': DashboardGuide(
    title: 'ایڈمن ڈیش بورڈ کی رہنمائی',
    intro: 'یہ ڈیش بورڈ مدرسے کے مکمل انتظامی کنٹرول کے لیے ہے۔ تمام اہم '
        'اعداد اور انتظامی حصے یہیں سے دستیاب ہیں۔',
    sections: [
      GuideSection(
        icon: Icons.bar_chart_outlined,
        heading: 'اہم اعداد و شمار',
        points: [
          'کل طلباء، اساتذہ اور کل عملہ: ادارے کی افرادی قوت۔',
          'آج حاضر: آج کی حاضری۔',
          'واجب الادا: بقایا فیس کی رقم۔',
        ],
      ),
      GuideSection(
        icon: Icons.grid_view_outlined,
        heading: 'انتظامی حصے',
        points: [
          'حاضری لگائیں: روزانہ حاضری درج کریں۔',
          'پیغامات دیکھیں اور پیغامات نشر کریں: اطلاعات بھیجیں۔',
          'جماعتیں و سیکشن: جماعتوں کا انتظام۔',
          'اسٹاف انتظام: عملے کا ریکارڈ۔',
          'امتحانی نتائج: نتائج دیکھیں اور شائع کریں۔',
          'رپورٹیں بنائیں اور پرنٹ کریں: ہر قسم کی رپورٹ۔',
          'عطیات و اخراجات: مالی لین دین۔',
          'کتابیں اور اجراء: لائبریری۔',
          'مکمل ڈیٹا ایک فائل میں: پورے ڈیٹا کا بیک اپ بنائیں۔',
        ],
      ),
      GuideSection(
        icon: Icons.history_outlined,
        heading: 'حالیہ سرگرمیاں',
        points: [
          'نظام میں ہونے والی تازہ سرگرمیوں کی فہرست یہاں نظر آتی ہے۔',
        ],
      ),
      GuideSection(
        icon: Icons.backup_outlined,
        heading: 'بیک اپ',
        points: [
          'بیک اپ حصے سے ڈیٹا محفوظ کریں تاکہ ضرورت پڑنے پر بحال کیا جا سکے۔',
        ],
      ),
    ],
  ),
  'parent': DashboardGuide(
    title: 'والدین ڈیش بورڈ کی رہنمائی',
    intro: 'یہ ڈیش بورڈ آپ کے بچے کی تعلیمی پیش رفت دیکھنے کے لیے ہے: '
        'حاضری، نمبرات اور فیس کی صورتحال۔',
    sections: [
      GuideSection(
        icon: Icons.family_restroom_outlined,
        heading: 'بچے کا انتخاب',
        points: [
          'اگر آپ کے ایک سے زیادہ بچے اس مدرسے میں پڑھتے ہیں تو اوپر سے بچہ منتخب کریں۔',
          'ہر بچے کا ریکارڈ الگ الگ نظر آئے گا۔',
        ],
      ),
      GuideSection(
        icon: Icons.dashboard_outlined,
        heading: 'خلاصہ کارڈز',
        points: [
          'اس ماہ حاضری: رواں ماہ میں بچے کی حاضری کا تناسب۔',
          'امتحانی نمبر: حالیہ امتحانات کے نمبرات۔',
          'فیس کی حالت: فیس ادا شدہ ہے یا بقایا ہے۔',
        ],
      ),
      GuideSection(
        icon: Icons.newspaper_outlined,
        heading: 'اپ ڈیٹس',
        points: [
          'آج کی اپ ڈیٹ: آج کی اہم معلومات۔',
          'آئندہ امتحانات: آنے والے امتحانات کی تاریخیں۔',
          'حالیہ سرگرمیاں: بچے کی حالیہ سرگرمیوں کا ریکارڈ۔',
        ],
      ),
      GuideSection(
        icon: Icons.receipt_long_outlined,
        heading: 'فیس کی تفصیل',
        points: [
          'فیس کی حالت کے کارڈ سے فیس کی مکمل تفصیل اور ادائیگی کی تاریخیں دیکھیں۔',
        ],
      ),
    ],
  ),
  'super_admin': DashboardGuide(
    title: 'سپر ایڈمن رہنمائی',
    intro: 'یہ پینل مدرسہ 360 کے فرنچائز نیٹ ورک کے جائزے کے لیے ہے۔ یہاں '
        'تمام مدارس کی مجموعی صورتحال نظر آتی ہے۔',
    sections: [
      GuideSection(
        icon: Icons.account_balance_outlined,
        heading: 'نیٹ ورک خلاصہ',
        points: [
          'کل مدارس: نیٹ ورک میں رجسٹرڈ مدارس کی تعداد۔',
          'فعال: اس وقت فعال مدارس۔',
          'پریمیم اور اسٹینڈرڈ: سبسکرپشن پلان کے حساب سے تقسیم۔',
        ],
      ),
      GuideSection(
        icon: Icons.manage_accounts_outlined,
        heading: 'مدرسہ مینجمنٹ',
        points: [
          'ہر مدرسے کی تفصیل دیکھیں اور انتظام کریں۔',
        ],
      ),
    ],
  ),
  'master': DashboardGuide(
    title: 'پلیٹ فارم کنسول کی رہنمائی',
    intro: 'یہ مدرسہ 360 پلیٹ فارم کے آپریٹرز کے لیے ہے۔ یہاں تمام مدارس، '
        'سبسکرپشنز اور نظام کی صحت کی نگرانی کی جاتی ہے۔',
    sections: [
      GuideSection(
        icon: Icons.subscriptions_outlined,
        heading: 'سبسکرپشنز',
        points: [
          'فعال: جاری سبسکرپشنز۔',
          'ٹرائل: آزمائشی مدت والے مدارس۔',
          'میعاد ختم اور معطل: توجہ طلب سبسکرپشنز۔',
        ],
      ),
      GuideSection(
        icon: Icons.people_outline,
        heading: 'تمام کرایہ داروں کے افراد',
        points: [
          'عملہ، طلبہ اور صارفین: تمام مدارس کے مجموعی اعداد۔',
        ],
      ),
      GuideSection(
        icon: Icons.health_and_safety_outlined,
        heading: 'سسٹم ہیلتھ',
        points: [
          'اے پی آئی خرابیاں، سائن ان ناکامیاں اور ہم آہنگی ناکامیاں (24 گھنٹے) یہاں نظر آتی ہیں۔',
          'کریش فری سیشنز: ایپ کے استحکام کا پیمانہ۔',
        ],
      ),
      GuideSection(
        icon: Icons.fact_check_outlined,
        heading: 'لائیو چیکس',
        points: [
          'یہ چیکس حقیقی وقت میں نظام کی حالت بتاتے ہیں — کبھی جعلی نہیں دکھائے جاتے۔',
        ],
      ),
      GuideSection(
        icon: Icons.menu_outlined,
        heading: 'مینیو',
        points: [
          'ڈراور سے مدارس کی فہرست، لائسنس، پلانز، ماڈیولز اور آڈٹ لاگز تک رسائی حاصل کریں۔',
        ],
      ),
    ],
  ),
  'generic': DashboardGuide(
    title: 'ڈیش بورڈ کی رہنمائی',
    intro: 'یہ آپ کا مرکزی ڈیش بورڈ ہے۔ یہاں سے اعلانات دیکھیں، اپنی '
        'پروفائل کھولیں اور روزانہ کے کاموں کا جائزہ لیں۔',
    sections: [
      GuideSection(
        icon: Icons.waving_hand_outlined,
        heading: 'خوش آمدید',
        points: [
          'اوپر آپ کا نام اور آپ کا کردار نظر آتا ہے۔',
          'دن کی ٹائم لائن میں آج کے اہم اوقات دیکھیں۔',
        ],
      ),
      GuideSection(
        icon: Icons.campaign_outlined,
        heading: 'تازہ اعلانات',
        points: [
          'انتظامیہ کے تازہ ترین اعلانات یہاں نظر آتے ہیں۔',
          'دیکھیں دبانے پر مکمل اعلان کھلتا ہے۔',
        ],
      ),
      GuideSection(
        icon: Icons.bolt_outlined,
        heading: 'فوری عمل',
        points: [
          'اعلانات: تمام اعلانات کی فہرست۔',
          'میری پروفائل: اپنی معلومات دیکھیں اور لاگ آؤٹ کریں۔',
          'پلیٹ فارم: پلیٹ فارم کنسول (صرف مجاز آپریٹرز کے لیے)۔',
        ],
      ),
    ],
  ),
};

/// Guide screen: step-by-step Urdu usage instructions for one dashboard.
class DashboardGuideScreen extends StatelessWidget {
  final String roleKey;

  const DashboardGuideScreen({super.key, required this.roleKey});

  @override
  Widget build(BuildContext context) {
    final guide = dashboardGuides[roleKey] ?? dashboardGuides['generic']!;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            'رہنمائی',
            style: AppTypography.appBarTitle.copyWith(color: Colors.white),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(guide.title, style: AppTypography.headingSmall),
            const SizedBox(height: 8),
            Text(guide.intro, style: AppTypography.bodyMedium),
            const SizedBox(height: 16),
            for (int i = 0; i < guide.sections.length; i++)
              _SectionCard(index: i, section: guide.sections[i]),
            const SizedBox(height: 8),
            Text(
              'مزید مدد کے لیے اپنی پروفائل سے لاگ آؤٹ کر کے دوبارہ لاگ اِن کریں یا منتظم سے رابطہ کریں۔',
              style: AppTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final int index;
  final GuideSection section;

  const _SectionCard({required this.index, required this.section});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(section.icon, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(section.heading, style: AppTypography.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final point in section.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(point, style: AppTypography.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// AppBar entry point: a ؟ button opening the guide for [roleKey].
class DashboardGuideButton extends StatelessWidget {
  final String roleKey;
  final Color? color;

  const DashboardGuideButton({super.key, required this.roleKey, this.color});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.help_outline, color: color),
      tooltip: 'رہنمائی',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DashboardGuideScreen(roleKey: roleKey),
        ),
      ),
    );
  }
}
