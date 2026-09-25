/// 真实 API 集成测试（手动运行: flutter test test/api_integration_test.dart）。
/// 原样复现用户操作链路: 搜索线路 → 线路详情 → 选中站实时。
/// 依赖网络；会触发接口限速（每步间隔 5 秒+），全程约 30 秒。
// ignore_for_file: avoid_print
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:my_bus_app/api/mybus_client.dart';

void main() {
  final client = MyBusClient();

  test('郴州: 搜索 → 详情 → 实时 全链路', () async {
    // 1. 搜索（同 SearchPage）
    final lines = await client.searchLine('郴州市', '1路');
    expect(lines, isNotEmpty, reason: 'CMD114 应有结果');
    print('搜索结果: ${lines.take(3).map((l) => "${l.lineName}(${l.upperOrDown})").join(', ')}');

    // 2. 线路详情（同 LineDetailPage._load）
    final l = lines.first;
    final detail = await client.lineStations('郴州市', l.lineName, l.upperOrDown);
    print('详情: ${detail.routeName} ${detail.stations.length}站 '
        'track=${detail.track.length} 首站="${detail.stations.first.showName}" '
        '末站="${detail.stations.lastOrNull?.showName}"');
    expect(detail.stations, isNotEmpty, reason: 'CMD103 应有站点');
    for (final s in detail.stations.take(3)) {
      print('  站${s.order} "${s.showName}" status=${s.status} lat=${s.lat} lon=${s.lon}');
    }

    // 3. 选中间站查实时（同 _selectStation/_fetchRt）
    final mid = detail.stations[detail.stations.length ~/ 2];
    final rt = await client.realtime('郴州市', l.lineName, l.upperOrDown, mid.order);
    print('实时: runState=${rt.runState} hasReal=${rt.hasReal} planTime=${rt.planTime} '
        'buses=${rt.buses.length} preds=${rt.predictions.length}');
    for (final b in rt.buses.take(2)) {
      print('  车 ${b.busNumber} index=${b.index} atStation=${b.atStation} '
          'lat=${b.lat} lng=${b.lng}');
    }
    for (final p in rt.predictions.take(2)) {
      print('  预测 ${p.busNumber} ${p.tips} ${p.timeTips} ${p.distTips}');
    }

    // 3.5 城市中心估算(免定位权限)
    final c = await client.cityCenterGuess('郴州市');
    print('cityCenterGuess 郴州市: $c');
    expect(c, isNotNull, reason: '郴州应有城市中心估算');

    // 4. 站点实时（同 StationBoardPage）
    final stationLines = await client.stationLines('郴州市', '火车站');
    print('火车站线路: ${stationLines.length} 条');
    expect(stationLines, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
