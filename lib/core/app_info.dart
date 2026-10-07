/// 应用元信息 —— **发版时和 `pubspec.yaml` 的 version 一起改**。
///
/// 为什么不从 pubspec 读：读它要引 `package_info_plus`（一个原生插件），
/// 只为在一个「关于」页上显示三行字，不值得多一个依赖。
/// 这里手写一份，和 pubspec 保持一致即可。
library;

const String kAppName = '一颗番茄';
const String kAppVersion = '2.1.0';

/// Android 的 **versionCode**（= `pubspec.yaml` 里 `version: x.y.z+N` 的那个 `N`）。
///
/// 为什么单列一个常量：检查更新时**只认 versionCode**（versionName 是给人看的，
/// 拿字符串比大小会出错）。以前只写了版本号字符串，更新检查就没法可靠比对。
/// `test/app_info_test.dart` 会拿它跟 pubspec 对账，防止漂移。
const int kAppVersionCode = 4;
// ⚠️ 2026-10-07 用户要求：不再出现作者署名 / 开源协议 / 数据存储相关的
// 常量或文案 —— 产品形态以后可能变（闭源收费 / 数据上传）。
// 现在这页只留名称和版本。
