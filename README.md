<div align="center">

# 🏋️ Gym Management System

### A premium, full-stack SaaS platform to run a gym like a business.

Members • Leads (CRM) • Billing • Attendance • Inventory • Reports — all in one unified dashboard.

![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Windows-1f6feb)
![Frontend](https://img.shields.io/badge/Frontend-Flutter-02569B?logo=flutter&logoColor=white)
![Backend](https://img.shields.io/badge/Backend-Node.js%20%2B%20Express-339933?logo=node.js&logoColor=white)
![Database](https://img.shields.io/badge/Database-MySQL-4479A1?logo=mysql&logoColor=white)
![Auth](https://img.shields.io/badge/Auth-JWT-000000?logo=jsonwebtokens&logoColor=white)

</div>

---

## ✨ Overview

A multi-tenant gym management ERP with a sleek **Obsidian × Gold × Emerald** dark theme, a fully
**mobile-responsive** UI, and a clean Node.js + MySQL backend. Built for real gym operations —
member lifecycles, lead nurturing, billing & partial payments, attendance check-ins, supplement
inventory, staff roles, and rich PDF reporting.

> Designed to compete with global products like Zenoti & Mindbody, scaled for local gyms.

---

## 🚀 Features

| Module | Highlights |
|---|---|
| **Dashboard** | Live KPIs (revenue, active members, dues), 7-day revenue chart, Active vs Expired donut, at-risk members, recent activity feed |
| **Leads (CRM)** | Lead temperature (Cold/Warm/Hot), fitness goals, referral source, follow-up scheduling, convert-to-member |
| **Members** | Lifecycle management, CNIC & emergency contacts, medical flags, DOB loyalty, QR codes, freeze/renew |
| **Plans** | Membership plans with duration, price, admission fee, active/inactive status |
| **Attendance** | Manual check-in kiosk + live member search, fees-pending guard |
| **Invoices** | Auto-invoice from member + plan, discounts (%/fixed), tax, payment status, PDF export |
| **Payments** | Manual payment recording with ledger re-evaluation (full → Paid, partial → balance tracking) |
| **Expenses** | Categorized expense ledger, payment source, receipt voucher attachment |
| **Inventory** | Products / supplements, stock movements, low-stock alerts, sell & track |
| **Reports** | Revenue prediction, Expense vs Revenue (profit margin), exportable PDFs |
| **Staff** | Role-based users — `owner`, `admin`, `staff`, `receptionist` |
| **Settings** | Gym profile, dynamic brand-color picker (any colour, persisted), WhatsApp reminders |

**Cross-cutting:** multi-tenant (gym code), JWT auth, WhatsApp due reminders, in-app PDF preview,
fully responsive (desktop + mobile), and a configurable backend URL.

---

## 🧱 Tech Stack

**Frontend — Flutter**
`Riverpod` (state) · `GoRouter` (routing) · `fl_chart` (charts) · `google_fonts` (Bebas Neue + Inter) ·
`printing` (PDF) · `qr_flutter` · `flutter_colorpicker` · `shared_preferences` · `url_launcher`

**Backend — Node.js**
`Express` · `mysql2` · `JWT` · `bcryptjs` · `zod` (validation) · `pdfkit` (PDF generation) · `cors` · `dotenv`

**Database** — MySQL 8

---

## 📂 Project Structure

```
gym_management_system/
├── lib/
│   └── src/
│       ├── core/          # theme, providers, api client, shared widgets
│       ├── features/      # dashboard, leads, members, plans, attendance,
│       │                  # billing, payments, expenses, inventory, reports,
│       │                  # staff, settings, auth, shell
│       └── models/        # data models
├── server/
│   ├── src/
│   │   ├── server.js      # Express API + routes + PDF generation
│   │   └── db.js          # MySQL pool (env-driven)
│   └── schema.sql         # database schema
├── DEPLOY.md              # one-time cloud deploy guide
└── start-server.bat       # Windows backend launcher
```

---

## ⚡ Getting Started (Local)

### Prerequisites
- [Flutter SDK](https://flutter.dev) (Dart ≥ 3.10)
- [Node.js](https://nodejs.org) (LTS) + npm
- [MySQL](https://dev.mysql.com/downloads/) 8

### 1. Database
```bash
mysql -u root -p -e "CREATE DATABASE gym_saas;"
mysql -u root -p gym_saas < server/schema.sql
```

### 2. Backend
```bash
cd server
# create server/.env (see "Environment Variables" below)
npm install
npm start                 # → API listening on http://0.0.0.0:8081
```

Create the first gym + admin (one time):
```bash
curl -X POST http://127.0.0.1:8081/dev/seed \
  -H "Content-Type: application/json" \
  -d '{"tenantSlug":"demo","tenantName":"Demo Gym","adminEmail":"admin@demo.com","adminPassword":"admin123","adminName":"Owner"}'
```

### 3. Frontend
```bash
flutter pub get
flutter run                       # desktop / connected device
# or build a shareable Android APK:
flutter build apk --release
```

### Default login
| Field | Value |
|---|---|
| Tenant / Gym Code | `demo` |
| Email | `admin@demo.com` |
| Password | `admin123` |

---

## 🔐 Environment Variables (`server/.env`)

```env
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=root
DB_PASSWORD=your_mysql_password
DB_NAME=gym_saas
JWT_SECRET=any-long-random-string
# Optional
DB_SSL=true            # for managed cloud MySQL
NODE_ENV=production    # locks the /dev/seed endpoint
```

---

## ☁️ Deployment & Sharing

The app talks to a backend, so a shared build needs a reachable server:

- **Production (recommended):** host the backend + MySQL once → see **[DEPLOY.md](DEPLOY.md)**.
  Set `kProductionApiUrl` in `lib/src/core/providers.dart`, rebuild — every APK then works with
  zero setup, anywhere.
- **Quick demo:** keep the backend local and expose it with a tunnel (e.g. ngrok), then build with
  `--dart-define=API_BASE_URL=https://your-tunnel-url`.

The app also ships an in-app **Server settings** field as an optional override.

---

## 🗺️ Roadmap

- [ ] One-click cloud deploy template
- [ ] iOS build
- [ ] Online payment gateway integration
- [ ] Push notifications for renewals & dues

---

<div align="center">

**Powered by [Deverosity](https://deverosity.com)**

</div>
