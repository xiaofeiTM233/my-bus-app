/// 复现「搜索 → 点结果 → 详情 → 返回」流程的 widget 测试（假客户端，无网络）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_bus_app/pages/search_page.dart';
import 'package:my_bus_app/state/app_state.dart';

import 'fake_client.dart';


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
