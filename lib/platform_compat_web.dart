import 'package:flutter/widgets.dart';

/// 全局根节点 key，与 IO 实现保持一致（Web 端截图自检不可用）。
final GlobalKey rootKey = GlobalKey();

/// Web 端：无进程环境变量，始终返回 null。
String? platformEnv(String key) => null;

/// Web 端：无法写文件，崩溃日志仅输出到控制台。
void installErrorLogging() {
  FlutterError.onError = (details) {
    debugPrint('\n[${DateTime.now()}] FLUTTER ${details.exception}');
    debugPrint('${details.stack}');
    FlutterError.presentError(details);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (e, st) {
    debugPrint('\n[${DateTime.now()}] UNCAUGHT $e\n$st');
    return true;
  };
}

/// Web 端：截图/退出自检不可用，空实现。
Future<void> scheduleSnapshot(String path) async {}
