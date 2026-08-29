# WariMesh — tonight's changes + filming guide

Written overnight while you slept, verified with `flutter analyze` (0 issues),
`flutter test` (passes), and `flutter build apk --debug` (succeeds) — so
Android Studio should just run it cleanly. Read this before you hit record.

## What changed

**1. Found the likely cause of "SOS has issues many times."**
Android emulators (and some real phones) don't implement real BLE
*peripheral/advertise* mode — only central/scan. So on your medium emulator,
every `Send SOS` was probably silently failing to actually broadcast
anything, with only a log line to show for it. That's not a bug you
introduced; it's a hardware/emulator limitation the old UI didn't surface
clearly.

**Fix: Demo Mode**, on by default, in the status card on the Home tab.
- The real BLE code path is untouched and still runs first — on a real
  phone with two devices it will genuinely try to send/relay over the air.
- On top of that, Demo Mode narrates simulated nearby phones picking up
  and relaying your alert (clearly tagged "(simulated)" in the log — never
  presented as a real transmission).
- The Activity Log screen also has a **"Simulate incoming"** button that
  feeds a fake alert through the *real* receive pipeline — real SQLite
  dedup, real relay decision, real Android notification. This is the best
  single shot for proving the notification actually fires, without needing
  a second phone.

**2. Added the Lost Person report feature you actually wanted.**
New "Missing" tab: name, age, a free-text description (appearance,
clothing, anything distinctive), last-seen location, optional contact
info, and a pick-a-color/icon avatar. Save it, and optionally broadcast a
lightweight alert beacon over the mesh at the same time. Tap into a report
for a detail view with a **"Mark as found"** button — good emotional beat
to end a demo clip on.

Why the description never leaves the phone that wrote it: the mesh packet
is a fixed 13 bytes (see `lib/models.dart` for the exact layout) — there's
no room for a name or a photo. That's a deliberate protocol constraint,
not a bug. The report screen says this plainly so it doesn't look like an
oversight on camera.

**3. Hardened startup so one failure can't silently break everything.**
Previously, permissions/notifications/database/BLE setup ran as one
unguarded sequence — if any single step threw (a very plausible explanation
for "sometimes it just doesn't work"), everything after it, including
`startScanning()`, never ran. Each step is now independently wrapped, logs
a warning if it fails, and lets the rest of startup continue. Bluetooth
being turned on *after* the app starts is also now handled — the app
watches adapter state and restarts scanning automatically instead of
staying dead until a restart.

**4. Full UI redesign.** Bottom-nav shell (Home / SOS / Missing), a proper
dashboard with live mesh status, a press-and-hold SOS button with a
countdown ring (harder to trigger by accident, reads well on camera), and
consistent card-based styling throughout. Code is split out of the
original single 641-line `main.dart` into `models.dart`,
`database_service.dart`, `mesh_service.dart`, `notification_service.dart`,
`foreground_service.dart`, `theme.dart`, `widgets.dart`, and one file per
screen under `lib/screens/`.

**5. Replaced the default Flutter launcher icon** with a small branded
mesh/signal glyph on the app's red, at every mipmap density
(`android/app/src/main/res/mipmap-*/ic_launcher.png`) — generated locally,
no external assets. Home screen and app switcher will show WariMesh
branding instead of the stock Flutter logo on camera.

**6. A clickable web mirror**, built so I could sanity-check the redesign
without your emulator:
https://claude.ai/code/artifact/aa5a0abf-593c-4369-8eb1-c40c88205e6b
It's a visual/flow reference only (plain HTML/JS, no real BLE/SQLite) — the
Android build is the real app. Every screen and every piece of copy in it
matches the Flutter build. It's private to your account; open it from any
browser, phone included.

## Offline Assistant (on-device LLM) — new

The volunteer shell now has a 4th tab, **Assistant**: a chat with Gemma-3n
E2B (int4) running fully on-device via Google's MediaPipe LLM Inference API
(`com.google.mediapipe:tasks-genai:0.10.27`). No network, no server — the
model answers first-aid / lost-person-search / crowd-safety questions from
the phone itself, and its system prompt is seeded with this phone's live
mesh status + active missing-person reports.

**The model file is NOT in the repo or the APK** (~3.7 GB, and the HF repo
is gated by Google's Gemma license). Two ways to get it onto the phone:

1. **In-app download (easiest)**: open the Assistant tab → "Download model
   (3.7 GB)". Needs internet once; requires the download URL to be
   reachable (see `kLlmModelDownloadUrl` in `lib/llm_service.dart` — a HF
   `resolve/main` URL, which works when the Gemma license is accepted for
   the downloading account, or when a public mirror is configured).
2. **adb push (most reliable for filming)**:
   ```bash
   # Download gemma-3n-E2B-it-int4.litertlm from
   # https://huggingface.co/google/gemma-3n-E2B-it-litert-lm (accept the
   # Gemma license; the file is the "gemma-3n-E2B-it-int4.litertlm" entry).
   # Push it into app-private storage. The exact path matters:
   adb shell run-as com.example.warimesh mkdir -p files/llm
   adb push gemma-3n-E2B-it-int4.litertlm \
     /sdcard/Download/gemma-3n-E2B-it-int4.litertlm
   adb shell run-as com.example.warimesh cp \
     /sdcard/Download/gemma-3n-E2B-it-int4.litertlm files/llm/
   ```
   (On a debug build, `run-as` works because the app is debuggable.
   Alternative without run-as: `adb root` on an emulator, or place the file
   in `/data/local/tmp/llm/` and change `LlmBridge.kt`'s `modelFile()`
   to read from there.)

First load takes several seconds (model is mmap'd into RAM); later loads
are fast. Generation streams token-by-token; on a mid-range phone expect
several seconds per response. The emulator generally **cannot** run the
model (MediaPipe needs a real GPU/CPU backend) — film on a physical phone.

E4B also exists (better answers, ~5 GB+ and slower) — swap the file +
`LlmBridge.kt`'s `MODEL_FILE` if you ever want it.

## Still true from before (unchanged, and still worth knowing)

Whether a foreground service actually keeps BLE scan/advertise alive with
the **screen locked** is still unverified — that code path wasn't touched.
**Keep the screen on and the app in the foreground while filming** to
sidestep the question entirely.

## Suggested shot list for the video

1. **Home tab** — mesh status card, point out "Listening for mesh traffic"
   and the Demo Mode badge.
2. **Report Missing** — fill in a name + description live on camera, save
   & broadcast. Cuts straight to the point of the app.
3. **Missing tab** — show the new report in the Active list.
4. **SOS tab** — press and hold the button, show the countdown ring, then
   the sent confirmation with the message ID/TTL.
5. **Activity Log → Simulate incoming** — tap "Simulate incoming → SOS."
   Show the phone's real notification firing. This is the most convincing
   single moment for proving the mesh pipeline actually works end to end.
6. **Missing tab → open a report → Mark as found** — good closing beat.

## If something looks off tonight/tomorrow morning

- `flutter analyze` and `flutter test` both pass as of this session — if
  Android Studio shows red squiggles, do a `flutter clean && flutter pub get`
  first; it's very likely a stale-cache issue, not a real error.
- If a real second phone becomes available before filming, real BLE send/
  receive should work as-is (Demo Mode doesn't disable it, it only adds
  narration on top) — turn Demo Mode off in that case so the log doesn't
  mix real and simulated hops.
