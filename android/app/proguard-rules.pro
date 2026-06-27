-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.mediapipe.**
-dontwarn com.google.protobuf.**
-dontwarn javax.annotation.processing.**
-dontwarn javax.lang.model.**

# ML Kit text recognition: the plugin references every language recognizer in
# its initialize() switch, but we only bundle Korean + Japanese (see app
# build.gradle). Keep ML Kit classes, and silence R8 over the Chinese/Devanagari
# recognizers we deliberately don't ship.
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
