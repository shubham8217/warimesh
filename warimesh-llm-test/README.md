# WariMesh LLM Test — native Android harness

A minimal standalone Android (Kotlin) app to test the on-device LLM
(Gemma-3n E2B via MediaPipe `tasks-genai`) **without Flutter**. Open this
folder in Android Studio, run it on a physical device, and chat with the
model directly.

It uses the exact same library, model file, and model path as the main
WariMesh app, so it doubles as a quick way to verify a downloaded model
before filming.

## Requirements

- Physical Android device (API 26+). **Emulators do not work** — MediaPipe
  LLM inference needs a real device.
- Android Studio (Ladybug or newer) with the Android SDK.
- A JDK 17/21/23. Gradle 8.14 cannot run on the Android-Studio-bundled
  JDK 25; the project pins `org.gradle.java.home` in `gradle.properties`
  to a Homebrew JDK 17 path (edit it if your JDK lives elsewhere, or
  override in `~/.gradle/gradle.properties`).
- The model file: `gemma-3n-E2B-it-int4.litertlm` (~3.7 GB) from
  https://huggingface.co/google/gemma-3n-E2B-it-litert-lm
  (gated by Google's Gemma license — accept it on Hugging Face first).

## Install the model

**Easiest — in-app download:** tap **Download model** in the app. It pulls
the 3.7 GB file over HTTPS with a live progress bar, then automatically
loads the model and unlocks the chat. Needs internet once.

**Important — the model repo is license-gated.** The download hits Hugging
Face's `resolve/main` URL, which returns HTTP 401/403 unless the request is
authenticated with a Hugging Face account that has accepted Google's Gemma
license. When you tap **Download model**, the app asks for a **Hugging Face
token** (create one at huggingface.co/settings/tokens, then accept the
Gemma license on the model page). The token is sent as a `Bearer` header
and stored in app-private storage only.

If you can't use a token, either:

- **Sideload over adb** (no internet needed on the phone):
  ```bash
  # 1. Build & install the app (or just press Run in Android Studio)
  ./gradlew installDebug

  # 2. Copy the model into app-private storage
  adb shell run-as com.example.warimeshllmtest mkdir -p files/llm
  adb push gemma-3n-E2B-it-int4.litertlm /sdcard/Download/
  adb shell run-as com.example.warimeshllmtest cp \
    /sdcard/Download/gemma-3n-E2B-it-int4.litertlm files/llm/
  ```
- **Point the app at a mirror/tokenized URL:** write the URL to
  `files/llm/model_url.txt` (via `adb run-as`) and the download button
  will use it instead of the default.

The app checks `files/llm/gemma-3n-E2B-it-int4.litertlm` on launch and
shows the expected path + push commands right on screen if it's missing.

## Run

1. Open this folder (`warimesh-llm-test/`) in Android Studio.
2. Plug in the phone, pick it as the target, press **Run**.
3. Tap **Load model** (first load takes several seconds; later ones are fast).
4. Type a prompt and press **Send** — the reply streams in token by token.

**Verified working** (emulator API 36, arm64): the model loads and answers
real questions correctly ("What is the capital of India" → "New Delhi…").
The reply filter strips Gemma's special tokens (`<end_of_turn>`) and
repeated-filler noise that the CPU backend can emit after the real answer.

### The assistant's system prompt

Every question is prefixed with a system prompt that makes the model a
**WariMesh field assistant for volunteers and warkaris**: it answers
emergency queries (snake bite, heat stroke, dehydration, dizziness,
wounds…) with **immediate numbered first-aid steps**, always ending with
**"contact a healthcare worker ASAP"** and a reminder that these are only
immediate suggestions, not professional medical advice. It stays short,
calm, and practical, and steers off-topic questions back to safety.
(Verified live: "A snake bit a warkari and there no doctor nearby" →
stay calm, immobilize the limb, keep the wound clean, watch for swelling/
breathing, monitor vitals, contact a healthcare worker ASAP.)

If the model is missing the app prints the exact `adb` commands to push it.

## Same model in the Flutter app

The main WariMesh app (`../`) expects the identical file name at the
identical path, so a model verified here works there too — only the
package name differs (`com.example.warimesh`).
