/// 横向站序条: 鼠标拖拽滚动 + 站点点击回调。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_bus_app/models/models.dart';
import 'package:my_bus_app/widgets/station_strip.dart';

LineDetail _detail(int n) => LineDetail(
      routeName: '测试线',
      upperOrDown: '1',
      comments: '',
      firstLast: const [],
      stations: List.generate(
        n,
        (i) => LineStation(
            showName: '第${i + 1}站',
            order: i + 1,
            lat: 25.86 + i * 0.001,
            lon: 113.04 + i * 0.001,
            status: 1,
            niheIndex: i),
      ),
      track: const [],
    );

void main() {
  testWidgets('鼠标拖拽可以滚动横向站序条', (tester) async {
    await tester.pumpWidget(MaterialApp(
      // 与全局一致的鼠标拖拽支持
      builder: (context, child) => ScrollConfiguration(
          behavior: const _MouseScrollBehavior(), child: child!),
      home: Scaffold(
        body: SizedBox(height: 150, child: StationStrip(detail: _detail(20), rt: null, currentOrder: 1)),
      ),
    ));
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final before = tester.state<ScrollableState>(scrollable).position.pixels;
    await tester.drag(scrollable, const Offset(-260, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    final after = tester.state<ScrollableState>(scrollable).position.pixels;

    expect(after, greaterThan(before), reason: '鼠标拖拽应能滚动站序条');
  });

  testWidgets('点击站点触发回调', (tester) async {
    int? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
            height: 150,
            child: StationStrip(
                detail: _detail(8), rt: null, currentOrder: 1,
                onStationTap: (o) => tapped = o)),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第3站'));
    expect(tapped, 3);
  });
}

class _MouseScrollBehavior extends MaterialScrollBehavior {
  const _MouseScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.invertedStylus,
      };
}
