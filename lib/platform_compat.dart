/// 平台兼容层：按编译目标自动选择实现。
/// - IO 平台（Android/iOS/Windows/Linux/macOS）：platform_compat_io.dart
/// - Web（JS/Wasm）：platform_compat_web.dart
library;

export 'platform_compat_io.dart'
    if (dart.library.js_interop) 'platform_compat_web.dart';
