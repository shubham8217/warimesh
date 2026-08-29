# WariMesh 🕉️📡

**WariMesh** is a Flutter app that helps pilgrims (*Warkaris*) and volunteers stay safe during a *Wari* (a large religious pilgrimage/walk) — even when there is **no internet and no mobile network**, which is very common in big crowds in rural areas.

It does this by turning nearby phones into a **Bluetooth mesh network**: an SOS or "Lost Person" alert hops from phone to phone over Bluetooth Low Energy (BLE) until it reaches a volunteer who can help — no SIM, no Wi-Fi, no server required.

> If you're new to Flutter or to this repo, this README is written for you. Follow it top to bottom.

---

## 🧠 What this app actually does

- **Two roles at sign-in:** `Warkari` (pilgrim) and `Volunteer`. Each role gets its own home screen.
- **SOS button:** A pilgrim in trouble taps SOS. The phone broadcasts a tiny alert packet over Bluetooth advertising. Nearby phones "hear" it, relay it further, and volunteers get a notification — even with the screen off.
- **Lost Person alerts:** Report someone missing; a lightweight beacon spreads through the mesh so volunteers nearby know to look out for them. The full name/photo/description stays local on the reporting phone (privacy by design) — only a short "look out for this" beacon travels over Bluetooth.
- **Mesh relay:** Every phone running the app automatically relays alerts it hears (with a hop limit / TTL), so a message can travel further than one phone's Bluetooth range.
- **Presence / headcount:** Phones also emit small "I'm here" beacons so volunteers get a rough sense of how many people are nearby.
- **Offline AI assistant ("Dindi"):** An on-device chat assistant (Gemma model running locally on Android) can answer questions without internet.
- **Advisories & activity log:** Volunteers can see mesh activity, alerts, and post advisories.

Because there's no server in the loop, **this is designed to work in places with zero connectivity**, which is the whole point.

---

## 🏗️ Tech stack

| Piece | What's used |
|---|---|
| Framework | [Flutter](https://flutter.dev) (Dart) |
| Bluetooth | `flutter_blue_plus` (scanning) + `flutter_ble_peripheral` (advertising) |
| Local storage | `sqflite` (SQLite) — desktop uses `sqflite_common_ffi` since Windows/Linux don't ship a native sqflite plugin |
| Background work | `flutter_foreground_task` — keeps the mesh relay alive when the app isn't in the foreground |
| Notifications | `flutter_local_notifications` |
| Location | `geolocator` (for sharing GPS location / directions in an SOS) |
| On-device AI | Android-native MediaPipe bridge running a local Gemma model (Android only) |

Platforms: primarily built for **Android** (real BLE mesh + AI assistant). It also runs on **Windows/desktop** for UI development — but Bluetooth mesh and the AI assistant only work on Android.

---

## 📁 Project structure (the important bits)

```
lib/
├── main.dart                 # App entry point, decides which screen to show first
├── models.dart                # Data models + the mesh "wire protocol" (the 15-byte BLE packet format)
├── mesh_service.dart          # Core Bluetooth mesh logic: scan, advertise, relay, dedup
├── database_service.dart      # SQLite storage (local-only data: profiles, lost reports, logs)
├── notification_service.dart  # Local push notifications for incoming alerts
├── location_service.dart      # GPS location for SOS
├── llm_service.dart           # On-device AI assistant ("Dindi")
├── foreground_service.dart    # Keeps mesh running in the background
├── theme.dart                 # App colors/fonts
└── screens/                   # All the UI screens (role select, login, SOS, chat, alerts, etc.)

test/                          # Automated tests (packet protocol, database, migrations, widgets)
windows/                       # Windows desktop build files (auto-generated, don't edit by hand)
android/                       # Android build files
```

You mostly only need to touch files inside `lib/`.

---

## ✅ Prerequisites (install these first)

1. **Flutter SDK** — [Install guide](https://docs.flutter.dev/get-started/install). This project needs Dart SDK `^3.11.0` (comes bundled with a recent Flutter).
2. **Git** — to clone/push code.
3. **An editor** — VS Code (with the Flutter extension) or Android Studio.
4. **For Android testing:** Android Studio + an Android phone (real Bluetooth needs a **real device**, not an emulator) with USB debugging enabled, or at least an emulator for basic UI checks.
5. Check everything is set up correctly:

```bash
flutter doctor
```

Fix anything it flags with a ❌ before continuing.

---

## 🚀 Running the app

```bash
# 1. Get into the project folder
cd warimesh

# 2. Install dependencies
flutter pub get

# 3. See connected devices (phone / emulator / windows)
flutter devices

# 4. Run it (pick a device if you have more than one connected)
flutter run
```

- To run on a specific device: `flutter run -d <device-id>` (get the id from `flutter devices`).
- To run on Windows desktop for quick UI iteration: `flutter run -d windows`.
- **Bluetooth mesh and the AI assistant only work on a real Android phone**, not on Windows/emulators.

### Running tests

```bash
flutter test
```

---

## 🔧 Common beginner issues

| Problem | Fix |
|---|---|
| `flutter: command not found` | Flutter isn't on your PATH — re-check the install guide for your OS. |
| No devices found | Plug in an Android phone with USB debugging on, or start an emulator from Android Studio. |
| Bluetooth permission errors on Android | The app requests permissions at runtime — accept all prompts (Location + Nearby Devices) when the app launches, they're required for BLE scanning/advertising on Android. |
| App builds on Windows but SOS/mesh does nothing | Expected — Bluetooth mesh is Android-only in this project. |
| `pub get` fails | Check your internet connection, or try `flutter clean && flutter pub get`. |

---

## 📤 Pushing your changes to GitHub

If you're new to Git, here's the exact sequence:

```bash
# 1. Check what changed
git status

# 2. Stage your changes
git add .

# 3. Commit with a clear message
git commit -m "Describe what you changed"

# 4. Push to GitHub
git push origin main
```

> ⚠️ If `main` is a protected/shared branch, create a feature branch instead:
> ```bash
> git checkout -b my-feature-name
> git push origin my-feature-name
> ```
> Then open a Pull Request on GitHub instead of pushing straight to `main`.

Repo: [github.com/shubham8217/warimesh](https://github.com/shubham8217/warimesh)

---

## 🩹 Project status

This is an active prototype. Notably:
- "Demo Mode" (a fake mesh simulator for filming without real hardware) has been removed — testing now requires real phones with Bluetooth.
- Syncing full Lost Person details (name/photo) across the mesh isn't built yet — today that data only travels when someone shows their phone directly to a volunteer.

---

## 🙋 Getting help

- Flutter basics: [docs.flutter.dev](https://docs.flutter.dev/)
- Dart language: [dart.dev](https://dart.dev/)
- Read the comments at the top of `lib/models.dart` and `lib/mesh_service.dart` — they explain the mesh protocol and design decisions in detail.
