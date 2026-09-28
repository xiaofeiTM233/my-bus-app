/// 应用信息。
/// 版本号需与 pubspec.yaml 的 version 保持一致；
/// 构建提交号由 CI/构建命令通过 `--dart-define=GIT_COMMIT=<sha>` 注入，
/// 本地直接构建时为空（不显示）。
library;

const appVersion = '1.0.1';
const repoUrl = 'https://github.com/xiaofeiTM233/my-bus-app';

const gitCommit = String.fromEnvironment('GIT_COMMIT');

/// 短提交号（7 位），未注入时返回空串。
String get commitShort => gitCommit.length >= 7 ? gitCommit.substring(0, 7) : gitCommit;
