/// 复现「搜索 → 点结果 → 详情 → 返回」流程的 widget 测试（假客户端，无网络）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_bus_app/api/mybus_client.dart';
import 'package:my_bus_app/models/models.dart';
import 'package:my_bus_app/pages/search_page.dart';
import 'package:my_bus_app/state/app_state.dart';

class FakeClient implements MyBusClient {
  @override
  Future<List<LineSummary>> searchLine(String city, String keyword) async => [
        LineSummary(
            lineName: '1路', upperOrDown: '1', from: '长冲铺', to: '兴义粮油市场', company: ''),
        LineSummary(
            lineName: '1路', upperOrDown: '2', from: '兴义粮油市场', to: '长冲铺', company: ''),
      ];

  @override
  Future<LineDetail> lineStations(String city, String lineName, String dir) async =>
      LineDetail(
        routeName: lineName,
        upperOrDown: dir,
        comments: '',
        firstLast: [FirstLast(first: '06:20', last: '18:40')],
        stations: List.generate(
          5,
          (i) => LineStation(
              showName: '站${i + 1}',
              order: i + 1,
              lat: 25.86 + i * 0.001,
              lon: 113.04 + i * 0.001,
              status: 1,
              niheIndex: i),
        ),
        track: const [],
      );

  @override
  Future<RealTime> realtime(
          String city, String lineName, String dir, int order) async =>
      RealTime(
          runState: 0,
          hasReal: 1,
          planTime: '12:00',
          stations: [],
          buses: [
            BusInfo(
                index: order - 1,
                busNumber: '湘L12345',
                statusType: '2',
                stationName: '站$order',
                lat: 25.861,
                lng: 113.041,
                niheIndex: 5,
                angle: 90,
                distToStation: 100,
                recTime: 0),
          ],
          disList: [],
          speedList: [],
          predictions: [
            RTimePrediction(
                busNumber: '湘L12345',
                count: 2,
                time: 5,
                distance: 800,
                tips: '2站',
                timeTips: '5分钟',
                distTips: '800米'),
          ]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('fake 未实现: ${invocation.memberName}');
}

void main() {
  testWidgets('输入即搜: onChanged 立即搜索', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(client: FakeClient());
    await app.load();
    await app.setCity('郴州市');

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: const MaterialApp(home: SearchPage()),
    ));

    await tester.enterText(find.byType(TextField), '1路');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsWidgets, reason: '输入变化应立即出结果');
  });

  testWidgets('搜索 → 点结果 → 详情出现 → 返回不崩溃', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(client: FakeClient());
    await app.load();
    await app.setCity('郴州市');

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: const MaterialApp(home: SearchPage()),
    ));

    await tester.enterText(find.byType(TextField), '1路');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsWidgets, reason: '搜索结果应出现');

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton<String>), findsOneWidget,
        reason: '线路详情页应已打开');

    await tester.pageBack();
    await tester.pumpAndSettle();
  });
}
