import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'pages/map_page.dart';
import 'pages/settings_page.dart';
import 'state/app_state.dart';
import 'state/map_store.dart';
import 'api/mybus_client.dart';
import 'platform_compat.dart';

const seedColor = Color(0xFF0A7D4F);

/// 各平台本地中文字体回退（按常见程度排序，逐个尝试直到命中系统已装字体）。
/// Web 端 CanvasKit 无法使用系统字体（走 /gstatic/ 同源代理），此列表无害。
const _systemFontFallback = <String>[
  'Microsoft YaHei', // Windows 微软雅黑
  'PingFang SC', // macOS 苹方
  'Noto Sans CJK SC', // Linux 思源黑体
  'WenQuanYi Micro Hei', // Linux 文泉驿微米黑
  'SimHei', // Windows 中易黑体
  'Heiti SC', // macOS 旧版黑体
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorLogging();
  final app = AppState(client: MyBusClient());
  await app.load();
  runApp(MyApp(app: app));
  final snapPath = platformEnv('ZSGJ_SNAPSHOT_PATH');
  if (snapPath != null) scheduleSnapshot(snapPath);
}

/// 桌面端允许鼠标拖拽滚动列表。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.invertedStylus,
      };
}

class MyApp extends StatelessWidget {
  final AppState app;
  const MyApp({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        // 常驻小地图与地图页共享的地图状态（同一张图）
        ChangeNotifierProvider(create: (_) => MapStore()),
      ],
      child: RepaintBoundary(
        key: rootKey,
        child: MaterialApp(
          title: '掌上公交',
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
            useMaterial3: true,
            // Windows 默认西文字体缺中文回退，观感差；桌面端固定微软雅黑
            fontFamily: defaultTargetPlatform == TargetPlatform.windows
                ? 'Microsoft YaHei'
                : null,
            // 各平台本地黑体系字体回退：系统已装则直接用，不依赖网络字体
            fontFamilyFallback: _systemFontFallback,
          ),
          home: const RootShell(),
        ),
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
