import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'pages/map_page.dart';
import 'pages/settings_page.dart';
import 'state/app_state.dart';
import 'api/mybus_client.dart';

const seedColor = Color(0xFF0A7D4F);
final GlobalKey _rootKey = GlobalKey();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState(client: MyBusClient());
  await app.load();
  runApp(MyApp(app: app));
  final snapPath = Platform.environment['ZSGJ_SNAPSHOT_PATH'];
  if (snapPath != null) _scheduleSnapshot(snapPath);
}

/// 开发自检：设置 ZSGJ_SNAPSHOT_PATH 后启动，8 秒后把整页渲染导出为 PNG 并退出。
/// （引擎内部取帧，不经屏幕合成，避免截到其他窗口。）
Future<void> _scheduleSnapshot(String path) async {
  await Future<void>.delayed(const Duration(seconds: 8));
  try {
    final boundary =
        _rootKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) exit(2);
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) exit(2);
    File(path).writeAsBytesSync(bytes.buffer.asUint8List());
  } finally {
    exit(0);
  }
}

class MyApp extends StatelessWidget {
  final AppState app;
  const MyApp({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        title: '掌上公交',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
          useMaterial3: true,
          // Windows 默认西文字体缺中文回退，观感差；桌面端固定微软雅黑
          fontFamily: defaultTargetPlatform == TargetPlatform.windows
              ? 'Microsoft YaHei'
              : null,
        ),
        home: RepaintBoundary(key: _rootKey, child: const RootShell()),
      ),
    );
  }
}

/// 底部 3 tab：首页 / 地图 / 我的。
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomePage(onGoMap: () => setState(() => _index = 1)),
          const MapPage(),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: '地图'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }
}
