# R8 规则 —— release 构建用

# google_mlkit_text_recognition 插件的 TextRecognizer.initialize() 里
# **引用了所有脚本**的 Options 类（拉丁 / 中文 / 天城文 / 日文 / 韩文），
# 但 App 侧只引入了自己需要的那一个（见 android/app/build.gradle.kts 的 dependencies）。
#
# debug 构建不做混淆，缺类不会报错；release 下 R8 会因为"Missing class"直接失败：
#   Missing class com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
#   Execution failed for task ':app:minifyReleaseWithR8'
#
# 我们确实不用这几个脚本，忽略即可 —— 比把它们的模型也打进来（多 4MB 左右）划算。
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ⚠️ ML Kit / Play Services 必须整体保留（2026-10-06 真机 + 模拟器 release 实测）：
#
# 只靠上面的 -dontwarn 时，release 包选图识别必现：
#   PlatformException: NullPointerException: Attempt to invoke virtual method
#   'java.lang.Object.getClass()' on a null object reference
#     at r71.<init>(r8-map-id-...) ...
# R8 full mode（proguard-android-optimize.txt）会把 ML Kit 通过反射/内部约定
# 引用的类裁掉或重排，构建期不报错、运行到识别才炸。debug 包不裁剪，所以
# 从来只在 release 上出现。
#
# 这两个包整个 keep 会让 APK 略大几 MB，但识别是课表导入的地基，稳定优先。
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
