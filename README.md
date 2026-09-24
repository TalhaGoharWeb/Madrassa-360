# Madrassa-360 (Al Markaz al Islami)

المرکز الاسلامی قصور - اسلامی تعلیمی اداروں کے لیے یکجا ERP نظام

Al Markaz al Islami Kasur - A unified ERP system for Islamic Educational Institutions

## Features
- **Role-Based Access Control**: Super Admin, Admin/Principal, Teacher, Parent/Student
- **Student & Staff Management**: Complete biodata, class assignments, and roles
- **Attendance & Results**: Daily attendance tracking, exam grading, report cards
- **Finance & Fees**: Fee voucher generation, payment collection, expense tracking
- **Library Management**: Book cataloging, issue and return workflow
- **Cloud Backend**: Powered by Supabase with Row Level Security (RLS)

## Setup & Configuration
1. Clone the repository:
   ```bash
   git clone https://github.com/TalhaGoharWeb/Madrassa-360.git
   cd Madrassa-360
   ```
2. Configure credentials:
   - Copy `assets/.env.example` to `assets/.env`
   - Fill in your `SUPABASE_URL` and `SUPABASE_ANON_KEY`
3. Install dependencies and run:
   ```bash
   flutter pub get
   flutter run
   ```

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
