import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_bus_app/models/models.dart';

void main() {
  test('stationNameHorizontal: 竖排括号转横排并收紧空格', () {
    expect(stationNameHorizontal('洋仕村口 ︵ 市中医院东 ︶'), '洋仕村口（市中医院东）');
    expect(stationNameHorizontal('泉州少林寺 ︵ 演武堂 ︶ '), '泉州少林寺（演武堂）');
    expect(stationNameHorizontal('田洋村'), '田洋村');
  });

  test('parseArrival: 即将到站', () {
    final a = parseArrival(nearText: '即将到站', nearDis: '小于1分钟/220米', nearTime: '', nearNum: 0);
    expect(a.state, ArrivalState.arriving);
  });

  test('parseArrival: N站+距离（nearnum=0 时从文本取站数）', () {
    final a = parseArrival(nearText: '5站', nearDis: '5分钟/1.5公里', nearTime: '', nearNum: 0);
    expect(a.state, ArrivalState.approaching);
    expect(a.stationsAway, 5);
    expect(a.minutesAway, 5);
    expect(a.distanceM, 1500);
    expect(a.summary, '5站/5分钟/1.5公里');
  });

  test('parseArrival: 停运/未发车', () {
    final a = parseArrival(nearText: '等待发车', nearDis: '', nearTime: '', nearNum: 0);
    expect(a.state, ArrivalState.noService);
    final b = parseArrival(nearText: '今日停运', nearDis: '', nearTime: '', nearNum: 0);
    expect(b.state, ArrivalState.noService);
  });

  test('parseArrival: 空文本 unknown', () {
    final a = parseArrival(nearText: '', nearDis: '', nearTime: '', nearNum: 0);
    expect(a.state, ArrivalState.unknown);
  });

  test('RealTime.fromJson: 实测样本（泉州41路）', () {
    const raw = '''
    {"runState":0,"hasReal":1,"planTime":"12:55",
     "data":[{"index":20,"arrive":0,"come":1,"stationName":"城西路北段"}],
     "list":[
       {"index":17,"busNumber":"闽C01295D","statusType":"2","stationName":"龙头山",
        "bus_lat":"24.914668937242002","bus_lng":"118.57442059216541",
        "nihePointIndex":246,"angle":91.97,"busToStationNiheDistance":202.77,
        "_recTime":1790309841436},
       {"index":6,"busNumber":"闽C01913D","statusType":"0","stationName":"洋仕村口",
        "bus_lat":"24.9020459","bus_lng":"118.5225620","nihePointIndex":-1,
        "angle":0.0,"busToStationNiheDistance":0.0,"_recTime":1790309842188}],
     "dislist":[{"d":1500.0}],
     "speedlist":[{"speed":300.0,"co":"green"}],
     "routeOnStationRTimeInfoList":[
       {"routeName":"41路","upperOrDown":"1","busToStationCount":4,
        "busToStationTime":4.0,"busToStationDistance":1500,
        "busToStationTips":"4站","busToStationTimeTips":"5分钟",
        "busToStationDistanceTips":"1.5公里","busNumber":"闽C01295D","planTime":"12:20"}]}
    ''';
    final rt = RealTime.fromJson(jsonDecode(raw));
    expect(rt.hasRealtime, isTrue);
    expect(rt.buses, hasLength(2));
    expect(rt.buses[0].atStation, isFalse);
    expect(rt.buses[1].atStation, isTrue);
    expect(rt.predictions, hasLength(1));
    expect(rt.predictions.first.busNumber, '闽C01295D');
    expect(rt.predictions.first.time, 4.0);
    expect(rt.speedList.first.co, 'green');
  });

  test('LineDetail.fromJson: 实测样本（泉州41路上行）', () {
    const raw = '''
    {"routeName":"41路","upperOrDown":"1","commonts":"",
     "firstLast":[{"first":"06:20","last":"18:40"}],
     "data":[
       {"showName":"田洋村","stationOrder":1,"station_lat":"24.90217245",
        "station_lon":"118.52257628","stationsStatus":1,"StationNihePointIndex":0},
       {"showName":"洋仕村口（市中医院东）","stationOrder":7,"station_lat":"24.9079",
        "station_lon":"118.5312","stationsStatus":2,"StationNihePointIndex":88}],
     "nihelist":[{"lat":"24.90217245","lng":"118.52257628"},
                 {"lat":"24.90413334","lng":"118.52381615"}]}
    ''';
    final d = LineDetail.fromJson(jsonDecode(raw));
    expect(d.routeName, '41路');
    expect(d.stations, hasLength(2));
    expect(d.stations[1].statusText, '只上不下');
    expect(d.track, hasLength(2));
    expect(d.firstLast.first.first, '06:20');
  });

  test('BusInfo.index 语义: index=17 → 站序18之前区间', () {
    const raw = '{"index":17,"busNumber":"X","statusType":"2"}';
    final b = BusInfo.fromJson(jsonDecode(raw));
    expect(b.index, 17);
  });
}
