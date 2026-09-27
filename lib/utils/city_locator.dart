/// 定位识别当前所在城市（供城市选择页「定位选城」使用）。
///
/// 流程：Geolocator 取 WGS-84 坐标 → wgs2gcj 转 GCJ-02（接口/底图坐标系）
/// → Nominatim 逆地理编码取城市名（免 key、全平台可用，失败不抛错返回空名）。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

import 'geo.dart';

class LocatedCity {
  /// 逆地理解析出的城市名（已去「市」后缀），空字符串 = 识别失败。
  final String name;

  /// 原始城市名（含「市」），用于展示。
  final String rawName;

  /// GCJ-02 坐标，可直接用于 CMD106 / 保存 lastLocation。
  final double gLat;
  final double gLng;

  LocatedCity({
    required this.name,
    required this.rawName,
    required this.gLat,
    required this.gLng,
  });
}

class CityLocator {
  /// 定位并识别城市。权限被拒/定位失败抛中文异常字符串；
  /// 仅逆地理失败不抛错（name 为空，调用方可做兜底）。
  Future<LocatedCity> locate() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      throw '定位权限被拒绝，无法定位选城';
    }
    if (perm == LocationPermission.deniedForever) {
      throw '定位权限被永久拒绝，请到系统设置中开启';
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw '定位服务未开启：手机请打开系统 GPS/位置服务；'
          'Windows 请在「设置→隐私和安全性→位置」中允许定位';
    }
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      // 实时定位失败（服务异常/信号弱）时退回系统缓存位置
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {
        pos = null;
      }
      if (pos == null) {
        throw '定位失败：$e\n请检查定位服务与权限后重试';
      }
    }
    final (gLat, gLng) = wgs2gcj(pos.latitude, pos.longitude);
    final raw = await _reverseCityName(pos.latitude, pos.longitude);
    return LocatedCity(
      name: _normalize(raw),
      rawName: raw,
      gLat: gLat,
      gLng: gLng,
    );
  }

  /// Nominatim 基址。原生端直连（可经 --dart-define=NOMINATIM_BASE 覆盖）；
  /// Web 端走同源 /nominatim/ 代理（Vercel Edge Function / dev_proxy.py），
  /// 规避国内直连 Nominatim 失败导致逆地理永远为空。
  static const _nominatimBase = String.fromEnvironment(
    'NOMINATIM_BASE',
    defaultValue: 'https://nominatim.openstreetmap.org',
  );

  /// Nominatim 逆地理（WGS-84 坐标）。任何失败返回 ''。
  Future<String> _reverseCityName(double lat, double lng) async {
    final base = kIsWeb ? '/nominatim' : _nominatimBase;
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      responseType: ResponseType.plain,
      headers: const {
        // Nominatim 使用政策要求可识别的 User-Agent
        'User-Agent': 'my-bus-app/1.0 (bus arrival query)',
      },
    ));
    try {
      final r = await dio.get<String>(
        '$base/reverse',
        queryParameters: {
          'format': 'jsonv2',
          'lat': lat.toStringAsFixed(6),
          'lon': lng.toStringAsFixed(6),
          'zoom': '10', // 城市级
          'accept-language': 'zh-CN',
        },
      );
      final d = jsonDecode(r.data ?? '') as Map<String, dynamic>;
      final addr = (d['address'] as Map?)?.cast<String, dynamic>();
      if (addr == null) return '';
      // 依次取：地级市 → 县级市/县 → 省会名（乡镇定位时 city 可能为空）
      for (final k in ['city', 'town', 'county', 'municipality', 'state']) {
        final v = addr[k]?.toString();
        if (v != null && v.isNotEmpty) return v;
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// 去掉「市」等后缀，便于与服务城市列表匹配。
  String _normalize(String name) => name
      .replaceAll(RegExp(r'(市|地区|自治州|盟)$'), '')
      .trim();
}
