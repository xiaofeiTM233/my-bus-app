/// 掌上公交接口客户端（h5.mygolbs.com，语义与限速规则见 docs/API.md）。
library;

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class MyBusException implements Exception {
  /// "-2"=城市不在服务范围；"98"=风控拦截（响应非 JSON）；"99"=网络错误。
  final String status;
  final String msg;
  MyBusException(this.status, this.msg);
  MyBusException.network(this.msg) : status = '99';

  bool get cityUnsupported => status == '-2';
  bool get blocked => status == '98';

  @override
  String toString() => 'MyBusException($status, $msg)';
}

class MyBusClient {
  static const api = 'https://h5.mygolbs.com/ApiData.do';
  static const origin = 'https://h5.mygolbs.com';

  final http.Client _http;
  final Duration minInterval;
  final Map<String, LineDetail> _lineCache = {};
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Random _rng = Random();

  MyBusClient({http.Client? client, this.minInterval = const Duration(seconds: 5)})
      : _http = client ?? http.Client();

  /// 全局限速：相邻请求间隔 ≥ minInterval + 0~300ms 抖动。
  Future<void> _throttle() async {
    final wait =
        minInterval + Duration(milliseconds: _rng.nextInt(300)) - DateTime.now().difference(_lastAt);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _lastAt = DateTime.now();
  }

  Future<dynamic> _post(Map<String, String> params) async {
    await _throttle();
    http.Response r;
    try {
      r = await _http.post(Uri.parse(api), body: params, headers: {'Origin': origin});
    } catch (e) {
      throw MyBusException.network('网络请求失败: $e');
    }
    if (r.statusCode != 200) {
      throw MyBusException.network('HTTP ${r.statusCode}');
    }
    final body = utf8.decode(r.bodyBytes);
    dynamic d;
    try {
      d = jsonDecode(body);
    } catch (_) {
      throw MyBusException('98', '接口风控拦截（响应异常），请稍后重试');
    }
    final status = d is Map ? d['status']?.toString() : null;
    if (status != '1') {
      throw MyBusException(status ?? '?', d is Map ? _s2(d['msg']) : '响应异常');
    }
    return d;
  }

  static String _s2(dynamic v) => v == null ? '' : v.toString();

  Map<String, String> _base(String city) => {'CITYNAME': city, 'CITYKEY': ''};

  /// CMD 101：全部服务城市。
  Future<List<City>> cityList() async {
    final d = await _post({'CMD': '101'});
    return [for (final e in (d['data'] as List?) ?? []) City.fromJson(e)];
  }

  /// CMD 106：附近站点。
  Future<List<NearbyStation>> nearby(String city, double lat, double lng) async {
    final d = await _post(_base(city)
      ..addAll({'CMD': '106', 'LAT': lat.toStringAsFixed(6), 'LNG': lng.toStringAsFixed(6)}));
    return [for (final e in (d['data'] as List?) ?? []) NearbyStation.fromJson(e)];
  }

  /// CMD 110：站点模糊搜索。
  Future<List<StationHit>> searchStation(String city, String keyword) async {
    final d = await _post(_base(city)..addAll({'CMD': '110', 'KEYWORD': keyword}));
    return [for (final e in (d['busstations'] as List?) ?? []) StationHit.fromJson(e)];
  }

  /// CMD 114：线路搜索。部分城市必须带「路」字，空结果自动补「路」重试。
  Future<List<LineSummary>> searchLine(String city, String keyword) async {
    final kw = keyword.trim();
    var d = await _post(_base(city)..addAll({'CMD': '114', 'KEYWORD': kw}));
    var lines = [for (final e in (d['buslines'] as List?) ?? []) LineSummary.fromJson(e)];
    if (lines.isEmpty && !kw.endsWith('路')) {
      d = await _post(_base(city)..addAll({'CMD': '114', 'KEYWORD': '$kw路'}));
      lines = [for (final e in (d['buslines'] as List?) ?? []) LineSummary.fromJson(e)];
    }
    return lines;
  }

  /// CMD 103：线路站点+轨迹（结果基本静态，按 城市|线路|方向 缓存）。
  Future<LineDetail> lineStations(String city, String lineName, String dir) async {
    final key = '$city|$lineName|$dir';
    final hit = _lineCache[key];
    if (hit != null) return hit;
    final d = await _post(_base(city)
      ..addAll({'CMD': '103', 'LINENAME': lineName, 'DIRECTION': dir}));
    final detail = LineDetail.fromJson(d);
    _lineCache[key] = detail;
    return detail;
  }

  /// CMD 115：站点各线路实时到站。[lat]/[lng] 用于同名站消歧。
  Future<List<StationLine>> stationLines(String city, String stationName,
      {String? lat, String? lng, bool all = false}) async {
    final d = await _post(_base(city)..addAll({
      'CMD': '115',
      'STATIONNAME': stationName,
      'MYLAT': lat ?? '',
      'MYLNG': lng ?? '',
      'ALL': all ? '1' : '0',
    }));
    return [for (final e in (d['data'] as List?) ?? []) StationLine.fromJson(e)];
  }

  /// CMD 104：某线路方向某站的实时车辆与到站预测。
  Future<RealTime> realtime(String city, String lineName, String dir, int order) async {
    final d = await _post(_base(city)..addAll({
      'CMD': '104',
      'LINENAME': lineName,
      'DIRECTION': dir,
      'STATIONORDER': '$order',
    }));
    return RealTime.fromJson(d);
  }
}
