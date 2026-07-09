# Gym Management System — UI / Styling / Layout Reference

> **Purpose of this document**
> A complete, self-contained snapshot of the app's **current** visual design system, layout structure, and component inventory. Hand this to another Claude (or designer) as the single source of truth when proposing a **UI layout redesign**.
>
> **Scope:** This is a Flutter app (Windows desktop + Android APK) with a Node/Express + MySQL backend. Only the **visual layer** is open for redesign. See [§12 Hard Constraints](#12-hard-constraints-do-not-break) — business logic, API contracts, providers, models, routes, and permission gates **must not change**.

---

## 1. What the app is

A multi-tenant **Gym Management ERP**. One codebase serves gym owners/admins/staff/receptionists. Core domains:

- **CRM** — Leads (prospects, temperature, follow-ups)
- **Members** — profiles, plans, membership expiry, at-risk tracking
- **Plans** — membership plan catalog
- **Attendance** — check-ins
- **Billing** — Invoices
- **Finance** — Payments, Expenses, Reports
- **Operations** — Inventory
- **Admin** — Staff, Settings
- **Dashboard** — KPIs, revenue charts, at-risk panel, activity feed

**Tech stack (UI-relevant):**
- Flutter (Dart ≥3.10), **Riverpod** (state), **GoRouter** (routing)
- `google_fonts` (Poppins), local **Grifter Bold** font asset
- `phosphor_flutter` (icons), `flutter_animate` / `animations` (motion)
- Custom design tokens in `lib/src/core/app_theme.dart`
- Global `ThemeData` (light + dark) built in `lib/src/app.dart`

---

## 2. Design language

A **dark-first, premium enterprise ERP** aesthetic — think Linear / Vercel / Retool discipline applied to a gym product.

- **Flat & minimal** — soft neutral shadows only. **No neon, no glow** anywhere (glow utilities were intentionally neutralized to return empty shadow lists).
- **Sharp but friendly geometry** — a single **15px** corner radius standard across cards, buttons, inputs, dialogs, chips.
- **Desktop-first**, but **fully mobile-responsive** (collapses to a drawer + card layouts).
- **Dynamic branding** — the owner can pick any accent color; it persists and re-themes the whole app live.
- **Both light and dark modes** are fully themed and toggleable.

---

## 3. Color system

### 3.1 Accent (primary)
| Token | Value | Notes |
|---|---|---|
| **Primary accent** | `#FE7A02` (signature orange) | Default. **Dynamic** — user can override via Settings color picker; persisted in SharedPreferences. Named `AppTheme.gold` in code for backward-compat. |
| Accent warm variant | `#FF922E` | Subtle shine/hover variant |

### 3.2 Dark mode canvas (default experience)
| Role | Value | Usage |
|---|---|---|
| Background (canvas) | `#1E1E1E` | `AppTheme.obsidian` — app scaffold |
| Surface / card | `#262628` | `AppTheme.charcoal` — cards, containers (one step above bg) |
| Elevated surface | `#2F2F32` | `AppTheme.charcoalHigh` — hover states, active rows |
| On-surface (text) | `#ECEDEF` | Primary text |
| On-surface variant | `#9AA0AA` | Secondary/muted text |
| Outline | `#3A3A3E` | Borders |
| Outline variant | `#313134` | Subtle dividers |

### 3.3 Light mode canvas
| Role | Value |
|---|---|
| Background | `#FFFFFF` |
| Surface / card | `#FFFFFF` |
| Surface container highest | `#F4F5F7` |
| Input fill | `#F1F2F4` |
| On-surface (text) | `#15181E` |
| On-surface variant | `#4B5563` |
| Outline | `#E5E7EB` |
| Outline variant | `#D1D5DB` |

### 3.4 Semantic colors (shared)
| Meaning | Value | Usage |
|---|---|---|
| Success / active | `#10B981` (emerald) | Active members, paid, health metrics |
| Success high-contrast | `#00E676` | Live status arcs |
| Warning | `#F59E0B` (amber) | At-risk, pending |
| Danger | `#FF5C5C` (dark) / `#B3261E` (light) | Errors, expired, delete |

### 3.5 Translucent border system (Linear/Vercel-style)
Borders are **white-at-rest**, accent only on selected/active state (accent is reserved for data, not chrome).
| Token | Value | Usage |
|---|---|---|
| `borderSubtle` | white 5% (`0x0DFFFFFF`) | Default card border |
| `borderHover` | white 8% (`0x14FFFFFF`) | Hover/focus border |
| `borderFocus` | white 25% (`0x40FFFFFF`) | Keyboard focus ring |

---

## 4. Typography (dual-font system)

| Role | Font | Where it's used |
|---|---|---|
| **Display / headings / KPI numbers / section titles / brand lockup** | **GRIFTER Bold** (local `assets/fonts/Grifter-Bold.ttf`, weight 700) | "76,975", "MEMBERS", "DASHBOARD", "AT-RISK MEMBERS", sidebar brand |
| **Body / data / labels / buttons / table rows / form fields** | **Poppins** (via `google_fonts`) | Member names, dates, list content, inputs, nav labels |

**Helper API** (`AppTypography` in `app_theme.dart`) — use these, don't hardcode:
- `kpiValue({color, fontSize=34, letterSpacing=0.4})` — Grifter, big metric numbers, height 1.05
- `sectionHeader({color, fontSize=16})` — Grifter, letterSpacing 0.6, section titles
- `brandTitle({color})` — Grifter 18, letterSpacing 0.8, sidebar brand
- `dataBody({color, fontSize=14, weight})` — Poppins, height 1.45, body text
- `uiLabel({color, fontSize=12, weight=w500, letterSpacing=0.2})` — Poppins, chips/timestamps/column headers
- `emphasisLabel({color, fontSize=14})` — Poppins w600, nav items/button labels

The global text theme (`_buildMixedTextTheme` in `app.dart`) applies Poppins as the base, then overlays Grifter on display/headline/title slots. Grifter is a **bold display face** (not condensed) — hierarchy comes from **size + weight**, tracking is modest.

---

## 5. Shape, radius & elevation

| Element | Radius token | Value |
|---|---|---|
| Cards, dialogs, inputs, buttons, chips, modals | `AppRadius.medium` / `large` | **15px** |
| Dense/small chips fallback | `AppRadius.small` | 12px |
| Sidebar nav tiles | `sidebarItemRadius` | 10px |
| Pills (segmented controls, status tags, avatars) | `AppRadius.pill` | 999 (full) |

**Elevation:** `AppTheme.cardShadow({hover})` — soft neutral black shadow only:
- Rest: black α22, blur 16, offset (0, 8)
- Hover: black α40, blur 24, offset (0, 12)

`AppTheme.neonGlow(...)` exists for API compatibility but **returns `[]`** — glow is dead app-wide.

---

## 6. Iconography

- **Phosphor "Regular"** icon set — **2px stroke, curved/rounded caps, soft, minimal**.
- Used **everywhere** (~461 usages, 16 files): sidebar, top bar, section headers, row actions, form headers, dialogs, empty states.
- **Zero** Material `Icons.*` remain in `lib/`.
- No glowing/filled icon containers — icons sit flat on tinted or transparent backgrounds.

Representative mappings:
| Context | Icon |
|---|---|
| Dashboard | `squaresFour` |
| Leads | `userList` |
| Members | `users` |
| Plans | `identificationCard` |
| Attendance | `userCheck` |
| Invoices | `receipt` |
| Payments | `wallet` |
| Expenses | `coins` |
| Reports | `chartBar` |
| Inventory | `package` |
| Staff | `identificationBadge` |
| Settings | `gearSix` |
| Refresh / search | `arrowClockwise` / `magnifyingGlass` |

---

## 7. Motion & animation

All motion lives in `lib/src/core/motion.dart` and is **gated** by `animationsEnabledProvider` (mirrors the Settings "Enable Animations" toggle). Off → instant static UI.

| Primitive | Behavior |
|---|---|
| **Page transitions** | `FadeThroughTransition` between routes (320ms in / 240ms reverse) |
| `AppEntrance({index})` | Fade + slight upward rise; `index` staggers items ~40ms apart (capped at 14) |
| `AnimatedCountUp({value, builder})` | Counts 0→value on first build (700ms, easeOutCubic) — used for KPI numbers |
| `Pressable({onTap})` | Press-scale to 0.97 (120ms) micro-interaction on tappable elements |

Charts animate a draw-in. Dashboard sections reveal in a staggered cascade.

---

## 8. Layout structure (App Shell)

`lib/src/features/shell/app_shell.dart` wraps every authenticated screen.

```
Desktop (≥900px):
┌───────────────────────────────────────────────────────┐
│ SIDEBAR (fixed) │ TOP BAR: refresh · theme · reminders │
│                 │         · global search · "+" · avatar│
│  Brand lockup   ├──────────────────────────────────────┤
│  Grouped nav ▾  │                                       │
│   Overview      │                                       │
│   CRM           │           ROUTED SCREEN CONTENT       │
│   Members       │                                       │
│   Billing       │                                       │
│   Finance       │                                       │
│   Operations    │                                       │
│   Admin         │                                       │
│  Owner profile  │                                       │
│  Powered by …   │                                       │
└───────────────────────────────────────────────────────┘

Mobile (<900px):
  Sidebar  → hamburger Drawer (same nav)
  Top bar  → compact AppBar (title FittedBox-scaled, compact icons)
```

**Sidebar nav** (order & routes, gated by role):
`Dashboard /dashboard` · `Leads /leads` · `Members /members` · `Plans /plans` · `Attendance /attendance` · `Invoices /invoices` · `Payments /payments` · `Expenses /expenses` · `Reports /reports` · `Inventory /inventory` · `Staff /staff` · `Settings /settings`

- Active nav tile: 10px radius, accent tint (α22) + thin accent border (α70) — the **one** place accent appears in chrome.
- Hover tile: flat white α5, no border/glow.
- Nav items conditionally shown by permission gates (`canManageStaff`, `canSeeSettings`, `canSeeRevenue`, `canSeeInventory`).

**Top bar globals:**
- Refresh, theme toggle, **Reminder Center** (badge w/ urgent count), **global search** (Ctrl/Cmd-K), **"+" Quick Actions** popover (Add Member / Add Lead / Quick Invoice / Record Expense), account avatar + logout.

---

## 9. Responsive system

| Breakpoint | Behavior |
|---|---|
| ~480px | KPI grid → single column |
| ~560–600px | Headers/filter strips stack or wrap |
| **900px** | Sidebar ↔ Drawer; DataTable ↔ card list; compact top bar |

- **Data tables → stacked cards** on mobile (name+status top, meta middle, actions bottom). No horizontal overflow, no single-letter wrapping.
- **KPI / action grids:** 3–4-up on desktop → 1 full-width column on phones.
- **Filter strips:** horizontally swipe-scrollable (`AppHScroll`) on mobile.
- **Charts:** 100% fluid, bounded inside their cards; labels always visible.
- Handles edge cases down to <300px (ellipsis, no overflow).

---

## 10. Shared component library (`lib/src/core/`)

| Component | Purpose |
|---|---|
| `FormRow` | Responsive 2-/3-column form field grid |
| `FormSectionLabel` | Section header + hint + icon inside forms |
| `FormSegmented<T>` | Pill segmented control (temperature, discount type, payment status) |
| `FormMultiChips` | Multi-select chips (fitness goals, medical conditions) |
| `AppFormDialog` / `showAppFormDialog` | Standard 15px modal frame for all add/edit forms |
| `AppHScroll` | Swipe-scroll filter strip container |
| `AppFilterPill` | Pill-shaped filter tag |
| `AppTableActionButton` | Row action buttons (view/edit/delete) |
| `AppDashedPanel` | Empty states / drop zones |
| `_MetricCard` | KPI tile (Grifter numeral, count-up) |
| `_DonutPiePainter` / `_RevenueChartPainter` | Custom-painted animated charts |
| `AppEntrance` / `AnimatedCountUp` / `Pressable` | Motion primitives (`motion.dart`) |
| `PoweredByDeverosity` | Branding footer link |

Theme is wired globally via `ThemeData` (`InputDecorationTheme`, `CardTheme`, `DialogTheme`, `FilledButtonTheme`, etc. all inherit the 15px radius + color scheme) — most screens restyle "for free" when tokens change.

---

## 11. Screen-by-screen layout patterns

**Dashboard** — hero banner (greeting + quick actions) → KPI metric grid (count-up numbers) → 7-day revenue line chart + active/expired donut → at-risk members panel → recent activity feed → insights. Sections reveal in staggered entrance cascade.

**List screens** (Members, Leads, Invoices, Payments, Expenses, Inventory, Plans, Staff) — page header (title + primary actions) → 4-up metric cards → filter bar (search + pills) → **DataTable (desktop) / card list (mobile)**.

**Forms** — modal dialogs (`AppFormDialog`) with `FormRow` grids, `FormSectionLabel`s, segmented/chip inputs, live totals (invoices), validators.

**Reports** — chart-heavy: revenue prediction + expense-vs-revenue with legend pills; PDF export tiles.

**Settings** — metric cards, gym profile, smart reminders (WhatsApp template), **theme toggle**, **brand accent-color picker**, sounds/animations toggles.

**Login** — split hero panel (desktop) / scrollable card (mobile): tenant + email + password, Server settings, animated branding.

---

## 12. Hard constraints (DO NOT break)

When redesigning the UI, treat the following as **frozen**:

- ❌ **No business logic changes** — calculations, validations, API calls, state flow.
- ❌ **No backend touches** — `server/`, `schema.sql`, `ApiClient` contracts.
- ❌ **Do not rename or remove**: route paths, provider names, model fields, feature actions.
- ❌ **Do not remove permission gates**: `requireRole`, `canSeeRevenue`, `canSeeInventory`, `canManageStaff`, `canSeeSettings` — the conditional nav/actions they drive must stay.
- ❌ **Keep the dynamic accent picker** — the accent must remain user-overridable (default `#FE7A02`).
- ❌ **Keep both light and dark themes** working.
- ❌ **Keep the animations toggle** — all motion must stay gated by `animationsEnabledProvider`.
- ✅ **Free to change**: color values, typography, spacing, radii, iconography, elevation, motion curves, component visual structure, layout composition, information hierarchy, responsive breakpoints.

**Files that own the visual layer** (safe to edit for a redesign):
- `lib/src/core/app_theme.dart` — tokens (colors, radii, typography helpers, decorations)
- `lib/src/app.dart` — global `ThemeData`, ColorSchemes, text theme, page transitions
- `lib/src/core/motion.dart` — motion primitives
- `lib/src/core/*` shared components (form_dialog, ui kit)
- `lib/src/features/**/**_screen.dart` — per-screen layout & composition
- `lib/src/features/shell/app_shell.dart` — sidebar / top bar / drawer
- `pubspec.yaml` — fonts & package declarations

---

## 13. Quick token cheat-sheet (for a redesign brief)

```
ACCENT      #FE7A02 (dynamic)         RADIUS      15px standard / 999 pill
DARK BG     #1E1E1E                   DARK CARD   #262628   DARK HOVER #2F2F32
LIGHT BG    #FFFFFF                   LIGHT CARD  #F4F5F7
TEXT (dark) #ECEDEF / muted #9AA0AA   TEXT (light) #15181E / muted #4B5563
SUCCESS     #10B981   WARNING #F59E0B   DANGER #FF5C5C
HEAD FONT   Grifter Bold              BODY FONT   Poppins
ICONS       Phosphor Regular, 2px, curved, minimal, no glow
SHADOW      soft neutral black only (no glow)
MOTION      fade-through pages, entrance stagger, KPI count-up, 0.97 press
```
