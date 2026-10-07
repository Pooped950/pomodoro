/// 应用元信息 —— **发版时和 `pubspec.yaml` 的 version 一起改**。
///
/// 为什么不从 pubspec 读：读它要引 `package_info_plus`（一个原生插件），
/// 只为在一个「关于」页上显示三行字，不值得多一个依赖。
/// 这里手写一份，和 pubspec 保持一致即可。
library;

const String kAppName = '一颗番茄';
const String kAppVersion = '2.0.0';
// ⚠️ 2026-10-07 用户要求：不再出现作者署名 / 开源协议 / 数据存储相关的
// 常量或文案 —— 产品形态以后可能变（闭源收费 / 数据上传）。
// 现在这页只留名称和版本。
