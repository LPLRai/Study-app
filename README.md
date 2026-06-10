# GYAN — AI Study Motivator & Helper

GYAN is a Flutter mobile app that helps students stay focused and study together.
It pairs a configurable Pomodoro workflow with study analytics, real‑time study
groups, and AI tools that generate quizzes and grade answer sheets.

> Status: `v1.0.0` · Flutter (Android‑first, iOS‑capable) · Firebase backend

---

## Features

**Focus & habits**
- Pomodoro focus timer with configurable focus / short‑break / long‑break lengths
  and cycle count, auto‑advancing phases with distinct end‑of‑phase sounds.
- App‑lock overlay (Android) that keeps you honest while a session runs.
- Ambient **white‑noise** sounds (rain, forest, cafe, ocean, fire) bundled offline.
- Per‑subject time tracking; sessions, **statistics** (daily / weekly / monthly,
  activity graph, top‑subjects breakdown), and a **streak calendar** with fire days.

**Study groups**
- Create or join groups by email **invite**.
- Live **leaderboard** (daily / weekly / all‑time) that updates in real time.
- Member profiles, a leader‑only sticky “add member” button, rename / edit group,
  remove members, and a slide‑in group‑info panel.

**Notifications**
- Group invites and “notify to study” nudges, delivered both **in‑app** and as
  real **phone push notifications** (FCM via a free push server — no Blaze plan).

**Profile & theme**
- Developer‑curated bundled **avatars** (no cloud storage needed).
- **Light / dark** theme (light by default), onboarding profile (grade, goals,
  strong/weak subjects).

**AI tools**
- **Quiz generator** — creates practice questions (Groq LLM).
- **Answer‑sheet analyzer** — OCR extracts the text from a photo, then a Groq
  model grades it with adjustable strictness.

**Admin panel** (restricted to allow‑listed emails)
- Adjust the admin’s own Pomodoro timings and stat overrides.
- View **registered / active / paid** user counts.
- Grant or revoke admin access by email.
- Send a **test notification** and **clean up** Firestore docs left by deleted
  accounts (keeps the registered count accurate).

---

## Tech stack

| Area | Technology |
|------|-----------|
| App | Flutter / Dart (SDK `>=3.2.0`) |
| State management | `provider` |
| Local cache | `shared_preferences` (offline‑first → instant cold start) |
| Auth | Firebase Authentication (email/password + email verification) |
| Database | Cloud Firestore (data + real‑time groups/leaderboard) |
| Push | Firebase Cloud Messaging + `flutter_local_notifications` |
| AI | Groq API (quiz generation + answer‑sheet grading) + an OCR API (photo → text) |
| Push server | Node.js + Express + `firebase-admin` (deployed free on Render) |
| Fonts | `google_fonts` (Inder bundled locally — no runtime fetch) |
| Media | `audioplayers`, `volume_controller`, `image_picker`, `image` |

> Note: Firebase **Storage** is intentionally **not** used. Avatars are bundled
> assets, and push runs on the small self‑hosted server, so the Firebase
> pay‑as‑you‑go (Blaze) plan is not required.

---

## Project structure

```
Study-app/
├─ README.md                  ← this file
└─ gyan_app/                  ← the Flutter app
   ├─ lib/
   │  ├─ main.dart            app entry + theme + auth gate
   │  ├─ config/admin_config.dart   root‑admin email allow‑list
   │  ├─ constants/           colours, bundled avatar list
   │  ├─ models/              user / subject / session / group
   │  ├─ providers/app_provider.dart   central app state
   │  ├─ services/            firebase, push, answer‑sheet (AI) services
   │  ├─ screens/             home, timer, groups, AI, profile, admin, stats…
   │  └─ widgets/             notifications panel, overlays, profile bits
   ├─ assets/                 audio, avatars, icon
   ├─ google_fonts/           bundled Inder-Regular.ttf
   ├─ push-server/            free FCM push + cleanup server (Node/Express)
   └─ functions/              (unused — logic moved to push-server)
```

---

## Quick start

### Prerequisites
- Flutter SDK `3.2+` and the Android SDK / Android Studio
- A Firebase project (Authentication + Cloud Firestore enabled)
- A **Groq** API key (quiz generation + answer‑sheet grading)
- An **OCR** API key (extracts text from answer‑sheet photos)

### 1. Install
```bash
cd gyan_app
flutter pub get
```

### 2. Connect Firebase
- Register an Android app in your Firebase project (package `com.example.gyan_app`)
  and place **`google-services.json`** in `gyan_app/android/app/`.
- Generate `lib/firebase_options.dart` with `flutterfire configure` (or keep the
  committed one if it points at your project).
- Enable **Email/Password** sign‑in and create a **Cloud Firestore** database.
- Publish Firestore security rules that:
  - let signed‑in users read user docs and read/write their own;
  - allow group reads, owner‑gated group writes, and member self‑writes;
  - restrict the `admins` collection to your root‑admin email(s).

### 3. Environment file (required)
Create **`gyan_app/.env`** (it is git‑ignored and bundled as an asset, so it must
exist for the app to build):
```
GROQ_KEY=your_groq_key            # quiz generator
GROQ_API_KEY_2=your_groq_key      # answer‑sheet grading (can reuse the same key)
OCR_API_KEY=your_ocr_key          # answer‑sheet photo → text
PUSH_ENDPOINT=                    # leave blank until the push server is deployed (step 5)
```

### 4. Run
```bash
flutter run
```

### 5. (Optional) Enable phone push notifications
Deploy the tiny push server and point the app at it — see
[`gyan_app/push-server/README.md`](gyan_app/push-server/README.md). In short:
- Deploy `gyan_app/push-server` on Render (free) with env vars
  `SERVICE_ACCOUNT` (the Firebase service‑account JSON) and `ADMIN_EMAILS`.
- Set `PUSH_ENDPOINT=https://YOUR-URL.onrender.com/send` in `.env` and rebuild.

If `PUSH_ENDPOINT` is empty, the app simply skips the push (in‑app notifications
still work) — nothing breaks before you deploy it.

### 6. (Optional) Become an admin
- Add your account email to `lib/config/admin_config.dart` → `rootAdminEmails`.
- Add the same email to `ADMIN_EMAILS` on the push server (needed for the
  “clean up deleted accounts” action).

---

## Building a release

For website distribution, build a single universal APK:
```bash
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

Before publishing publicly:
- **Set up a real release keystore** (the release build is currently signed with
  the debug key) so future updates are accepted by Android.
- **Restrict your API keys** — `.env` is bundled inside the APK and can be
  extracted, so add provider‑side key restrictions / quotas (or proxy AI calls
  through a server).
- Bump `version:` in `pubspec.yaml` for each release.

---

## Security notes
- `.env` and any service‑account JSON are git‑ignored — never commit them.
- The push server verifies the caller’s Firebase ID token, and the purge/admin
  actions additionally require an allow‑listed admin email.
- `google-services.json` and `firebase_options.dart` are client config (safe to
  ship); they are protected by your Firestore security rules.
