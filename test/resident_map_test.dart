/// 「地图常驻」开启时：线路详情页与站牌页顶部应出现常驻地图。
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_bus_app/pages/line_detail_page.dart';
import 'package:my_bus_app/pages/station_board_page.dart';
import 'package:my_bus_app/state/app_state.dart';

import 'fake_client.dart';

Future<AppState> _readyApp() async {
  SharedPreferences.setMockInitialValues({});
  final app = AppState(client: FakeClient());
  await app.load();
  await app.setCity('郴州市');
  await app.setMapAlwaysOn(true);
  return app;
}

void main() {
  testWidgets('线路详情页顶部出现常驻地图', (tester) async {
    final app = await _readyApp();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: const MaterialApp(home: LineDetailPage(lineName: '1路', dir: '1')),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsWidgets,
        reason: '地图常驻开启时详情页顶部应有地图');
  });

  testWidgets('站牌页站牌模式顶部出现常驻地图', (tester) async {
    final app = await _readyApp();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: const MaterialApp(home: StationBoardPage(stationName: '火车站')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first); // 进入站牌模式
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsWidgets,
        reason: '地图常驻开启时站牌模式顶部应有地图');
  });
}
