import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 全局根节点 key，用于整页截图自检。
final GlobalKey rootKey = GlobalKey();

/// 桌面端：读取进程环境变量。
String? platformEnv(String key) => Platform.environment[key];

/// 崩溃/未捕获异常落盘（%APPDATA%\my_bus_app\crash.log），便于事后定位。
void installErrorLogging() {
  final dir = Directory(
      '${Platform.environment['APPDATA'] ?? Directory.systemTemp.path}\\my_bus_app');
  void write(String msg) {
    try {
      dir.createSync(recursive: true);
      File('${dir.path}\\crash.log')
          .writeAsStringSync(msg, mode: FileMode.append);
    } catch (_) {}
  }

  FlutterError.onError = (details) {
    write('\n[${DateTime.now()}] FLUTTER ${details.exception}\n${details.stack}\n');
    FlutterError.presentError(details);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (e, st) {
    write('\n[${DateTime.now()}] UNCAUGHT $e\n$st\n');
    return true;
  };
}

/// 开发自检：设置 ZSGJ_SNAPSHOT_PATH 后启动，8 秒后把整页渲染导出为 PNG 并退出。
/// （引擎内部取帧，不经屏幕合成，避免截到其他窗口。）
Future<void> scheduleSnapshot(String path) async {
  await Future<void>.delayed(const Duration(seconds: 8));
  try {
    final ctx = rootKey.currentContext;
    final boundary =
        ctx?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      File('$path.err').writeAsStringSync('boundary null, ctx=$ctx', mode: FileMode.append);
      exit(2);
    }
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      File('$path.err').writeAsStringSync('toByteData null', mode: FileMode.append);
      exit(2);
    }
    File(path).writeAsBytesSync(bytes.buffer.asUint8List());
  } catch (e, st) {
    File('$path.err').writeAsStringSync('snapshot failed: $e\n$st',
        mode: FileMode.append);
  } finally {
    exit(0);
  }
}
