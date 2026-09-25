/// 测试用假客户端：即时返回固定数据，无网络。
library;

import 'package:dio/dio.dart';
import 'package:my_bus_app/api/mybus_client.dart';
import 'package:my_bus_app/models/models.dart';

class FakeClient implements MyBusClient {
  @override
  Future<List<LineSummary>> searchLine(String city, String keyword,
      {CancelToken? cancelToken}) async => [
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
  Future<List<StationHit>> searchStation(String city, String keyword,
      {CancelToken? cancelToken}) async => [
        StationHit(stationName: '火车站', sameNameNum: 2),
        StationHit(stationName: '街洞火车站', sameNameNum: 0),
      ];

  @override
  Future<List<StationLine>> stationLines(String city, String stationName,
      {String? lat, String? lng, bool all = false}) async =>
      [
        StationLine(
            lineName: '32路',
            upperOrDown: '2',
            nearText: '即将到站',
            nearDis: '小于1分钟/200米',
            nearTime: '',
            nearNum: 0,
            stationOrder: 5),
        StationLine(
            lineName: '4路',
            upperOrDown: '1',
            nearText: '3站',
            nearDis: '6分钟/2公里',
            nearTime: '',
            nearNum: 3,
            stationOrder: 8),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('fake 未实现: ${invocation.memberName}');
}
