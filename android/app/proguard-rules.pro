# R8/ProGuard rules for release builds.
#
# Without this file `flutter build apk --release` fails outright: R8 refuses
# to finish because MediaPipe's on-device LLM classes reference AutoValue
# annotations that are not on the runtime classpath.
#
#   Missing class com.google.auto.value.AutoValue
#     (referenced from com.google.mediapipe.tasks.genai.llminference...)
#
# AutoValue is a COMPILE-TIME code generator. Its annotations have source/
# class retention and are never needed at runtime, so the reference being
# absent is expected rather than a real missing dependency. -dontwarn is the
# correct response: it silences the warning without keeping anything, and
# without weakening shrinking anywhere else.
#
# Deliberately narrow. A blanket `-dontwarn **` would have made this build
# succeed too, and would have hidden the next genuinely missing class.
-dontwarn com.google.auto.value.AutoValue
-dontwarn com.google.auto.value.AutoValue$Builder
