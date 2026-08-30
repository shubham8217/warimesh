# R8/ProGuard rules for release builds.
#
# NOTE: minification is currently DISABLED for release (see
# build.gradle.kts). These rules are kept, and kept correct, because they
# are what any future attempt to re-enable shrinking will need on day one.
#
# --------------------------------------------------------------------------
# Why minification was turned off, recorded so nobody turns it back on
# without reading this.
#
# Two separate failures, both from MediaPipe's on-device LLM:
#
# 1. R8 refused to finish at all:
#      Missing class com.google.auto.value.AutoValue
#        (referenced from com.google.mediapipe.tasks.genai.llminference...)
#    AutoValue is a compile-time generator whose annotations are never
#    present at runtime, so -dontwarn is the correct response.
#
# 2. With that silenced the build succeeded and the app then broke on a real
#    phone the moment the assistant was opened:
#      field modelPath for b1.g not found
#    `b1.g` is an obfuscated name. LlmInferenceOptions is an AutoValue class
#    and MediaPipe resolves its fields BY NAME at runtime, so renaming them
#    is fatal — and it is invisible until someone actually opens the
#    assistant, which no unit test and no startup check will do.
#
# The keep rules below are believed sufficient, but "believed" is the
# problem: every one of them is a guess about which classes MediaPipe
# reflects on, and the failure mode is a feature that looks fine until it is
# demonstrated. Shrinking buys a smaller APK; it is not worth an assistant
# that breaks on stage.
# --------------------------------------------------------------------------

# AutoValue: compile-time only, never present at runtime.
-dontwarn com.google.auto.value.AutoValue
-dontwarn com.google.auto.value.AutoValue$Builder

# MediaPipe resolves fields and classes by name at runtime — nothing under
# it may be renamed or stripped.
-keep class com.google.mediapipe.** { *; }
-keep interface com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# AutoValue's generated implementations, which carry the fields MediaPipe
# looks up (modelPath among them).
-keep class **.AutoValue_* { *; }

# Protobuf, used by MediaPipe's task graphs, is also reflection-heavy.
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**
