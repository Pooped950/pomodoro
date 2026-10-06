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
