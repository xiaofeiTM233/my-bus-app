import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'pages/map_page.dart';
import 'pages/settings_page.dart';
import 'state/app_state.dart';
import 'api/mybus_client.dart';
import 'platform_compat.dart';

const seedColor = Color(0xFF0A7D4F);

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
    return ChangeNotifierProvider.value(
      value: app,
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
