/// 掌上公交接口客户端（h5.mygolbs.com，字段语义见 docs/API.md）。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/models.dart';

class MyBusException implements Exception {
  /// "-2"=城市不在服务范围；"97"=请求已取消；"98"=风控拦截（响应非 JSON）；"99"=网络错误。
  final String status;
  final String msg;
  MyBusException(this.status, this.msg);
  MyBusException.network(this.msg) : status = '99';

  bool get cityUnsupported => status == '-2';
  bool get blocked => status == '98';
  bool get cancelled => status == '97';

  @override
  String toString() => 'MyBusException($status, $msg)';
}

class MyBusClient {
  static const api = 'https://h5.mygolbs.com/ApiData.do';
  static const origin = 'https://h5.mygolbs.com';

  /// Web 端请求端点：走同源 Edge Function 代理（api/ApiData.do.js）。
  /// 浏览器禁止 JS 设置 Origin（受保护头），且直连时浏览器自动携带的
  /// Origin 是本站域名，过不了接口风控（实测错误 Origin 返回加密垃圾），
  /// 因此必须由服务端代理注入 Origin: h5.mygolbs.com。
  /// 本地联调可用 --dart-define=WEB_API_ENDPOINT=... 指向其他代理地址。
  static const webApi = String.fromEnvironment(
    'WEB_API_ENDPOINT',
    defaultValue: '/api/ApiData.do',
  );

  String get _endpoint => kIsWeb ? webApi : api;

  final Dio _dio;
  final Map<String, LineDetail> _lineCache = {};

  MyBusClient({Dio? dio}) : _dio = dio ?? _createDio();

  static Dio _createDio() => Dio(
    BaseOptions(
      // Web 端不设 Origin（浏览器拒绝设置受保护头），由代理端注入
      headers: kIsWeb ? const <String, String>{} : {'Origin': origin},
      contentType: 'application/x-www-form-urlencoded',
      responseType: ResponseType.bytes, // 手动 utf8 解码，防 latin1 默认
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  Future<dynamic> _post(
    Map<String, String> params, {
    CancelToken? cancelToken,
  }) async {
    Response<List<int>> r;
    try {
      r = await _dio.post<List<int>>(
        _endpoint,
        data: params,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.cancel:
          throw MyBusException('97', '请求已取消');
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          throw MyBusException.network('请求超时');
        default:
          throw MyBusException.network('网络请求失败: ${e.message ?? e.type.name}');
      }
    }
    if (r.statusCode != 200) {
      throw MyBusException.network('HTTP ${r.statusCode}');
    }
    final body = utf8.decode(r.data ?? const []);
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
  Future<List<NearbyStation>> nearby(
    String city,
    double lat,
    double lng,
  ) async {
    final d = await _post(
      _base(city)..addAll({
        'CMD': '106',
        'LAT': lat.toStringAsFixed(6),
        'LNG': lng.toStringAsFixed(6),
      }),
    );
    return [
      for (final e in (d['data'] as List?) ?? []) NearbyStation.fromJson(e),
    ];
  }

  /// CMD 110：站点模糊搜索。
  Future<List<StationHit>> searchStation(
    String city,
    String keyword, {
    CancelToken? cancelToken,
  }) async {
    final d = await _post(
      _base(city)..addAll({'CMD': '110', 'KEYWORD': keyword}),
      cancelToken: cancelToken,
    );
    return [
      for (final e in (d['busstations'] as List?) ?? []) StationHit.fromJson(e),
    ];
  }

  /// CMD 114：线路搜索。部分城市必须带「路」字，空结果自动补「路」重试。
  Future<List<LineSummary>> searchLine(
    String city,
    String keyword, {
    CancelToken? cancelToken,
  }) async {
    final kw = keyword.trim();
    var d = await _post(
      _base(city)..addAll({'CMD': '114', 'KEYWORD': kw}),
      cancelToken: cancelToken,
    );
    var lines = [
      for (final e in (d['buslines'] as List?) ?? []) LineSummary.fromJson(e),
    ];
    if (lines.isEmpty && !kw.endsWith('路')) {
      d = await _post(
        _base(city)..addAll({'CMD': '114', 'KEYWORD': '$kw路'}),
        cancelToken: cancelToken,
      );
      lines = [
        for (final e in (d['buslines'] as List?) ?? []) LineSummary.fromJson(e),
      ];
    }
    return lines;
  }

  /// CMD 103：线路站点+轨迹（结果基本静态，按 城市|线路|方向 缓存）。
  Future<LineDetail> lineStations(
    String city,
    String lineName,
    String dir,
  ) async {
    final key = '$city|$lineName|$dir';
    final hit = _lineCache[key];
    if (hit != null) return hit;
    final d = await _post(
      _base(city)
        ..addAll({'CMD': '103', 'LINENAME': lineName, 'DIRECTION': dir}),
    );
    final detail = LineDetail.fromJson(d);
    _lineCache[key] = detail;
    return detail;
  }

  /// 城市中心估算（无需定位权限）：搜「1」取任一城市线路，站点坐标求质心。
  /// 失败（城市无数据/网络异常）返回 null。
  Future<(double, double)?> cityCenterGuess(String city) async {
    try {
      final lines = await searchLine(city, '1');
      if (lines.isEmpty) return null;
      final l = lines.first;
      final dir = l.upperOrDown.isEmpty ? '1' : l.upperOrDown;
      final d = await lineStations(city, l.lineName, dir);
      final pts = d.stations.where((s) => s.lat != 0 && s.lon != 0).toList();
      if (pts.isEmpty) return null;
      final lat = pts.map((s) => s.lat).reduce((a, b) => a + b) / pts.length;
      final lng = pts.map((s) => s.lon).reduce((a, b) => a + b) / pts.length;
      return (lat, lng);
    } catch (_) {
      // 城市无数据 / 网络异常 / 风控拦截，一律视为无法估算
      return null;
    }
  }

  /// CMD 115：站点各线路实时到站。[lat]/[lng] 用于同名站消歧。
  Future<List<StationLine>> stationLines(
    String city,
    String stationName, {
    String? lat,
    String? lng,
    bool all = false,
  }) async {
    final d = await _post(
      _base(city)..addAll({
        'CMD': '115',
        'STATIONNAME': stationName,
        'MYLAT': lat ?? '',
        'MYLNG': lng ?? '',
        'ALL': all ? '1' : '0',
      }),
    );
    return [
      for (final e in (d['data'] as List?) ?? []) StationLine.fromJson(e),
    ];
  }

  /// CMD 104：某线路方向某站的实时车辆与到站预测。
  Future<RealTime> realtime(
    String city,
    String lineName,
    String dir,
    int order,
  ) async {
    final d = await _post(
      _base(city)..addAll({
        'CMD': '104',
        'LINENAME': lineName,
        'DIRECTION': dir,
        'STATIONORDER': '$order',
      }),
    );
    return RealTime.fromJson(d);
  }
}
