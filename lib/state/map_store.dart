/// 首页常驻地图与地图页共享的地图状态。
///
/// 两处地图读写同一份「我的位置 / 附近站点 / 相机」，
/// 定位与附近站点只请求一次，相机在两张地图间同步——
/// 从常驻小地图切到全屏地图是无缝的同一张图，不再各自为政。
library;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../utils/city_locator.dart' show getSmartPosition;
import '../utils/geo.dart';
import 'app_state.dart';

class MapStore extends ChangeNotifier {
  /// 我的位置 / 城市中心（GCJ-02）
  LatLng? me;

  /// 附近站点（真实定位成功后拉取）
  List<NearbyStation>? nearby;

  /// 已对准的城市（IndexedStack 常驻，切城后重新对准）
  String locatedCity = '';

  /// 状态提示（地图页底部卡片展示；常驻小地图静默不打扰首页）
  String hint = '';

  bool locating = false;

  /// 共享相机：任一地图手势结束时记录，另一张地图随后对齐
  LatLng? camCenter;
  double camZoom = 12;

  static const defaultCenter = LatLng(24.91, 118.58);

  /// 手势结束后由地图上报相机（不 notify，避免两张地图互踢）。
  void reportCamera(LatLng center, double zoom) {
    camCenter = center;
    camZoom = zoom;
  }

  void _moveCamera(LatLng c, double zoom) {
    camCenter = c;
    camZoom = zoom;
    notifyListeners();
  }

  /// 直接展示一条提示（带通知）。
  void showHint(String msg) {
    hint = msg;
    notifyListeners();
  }

  /// 确保对准当前城市：已授权定位→真实定位；未授权→城市中心（缓存→估算）。
  /// [silent] 常驻小地图用：失败不写提示。
  Future<void> ensureCity(AppState app, {bool silent = true}) async {
    if (locating || !app.ready || app.city == locatedCity) return;
    locatedCity = app.city;
    nearby = null;
    notifyListeners();
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        await _getCurrentAndQuery(app);
        return;
      }
    } catch (_) {
      // 桌面端可能无定位插件支持，落到城市中心
    }
    await _toCityCenter(app, silent);
  }

  /// 定位按钮：请求权限 → 定位 → 拉附近站点。失败写 hint（不抛出）。
  Future<void> locate(AppState app) async {
    if (locating) return;
    if (!app.ready) {
      hint = '请先在首页选择城市';
      notifyListeners();
      return;
    }
    locating = true;
    notifyListeners();
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw '定位权限被拒绝';
      }
      locatedCity = app.city;
      await _getCurrentAndQuery(app);
    } catch (e) {
      hint = '定位失败：$e';
    } finally {
      locating = false;
      notifyListeners();
    }
  }

  Future<void> _getCurrentAndQuery(AppState app) async {
    // 智能取位：缓存位置优先，避免室内等 GPS 锁定十几秒
    final pos = await getSmartPosition();
    final (gLat, gLng) = wgs2gcj(pos.latitude, pos.longitude);
    me = LatLng(gLat, gLng);
    hint = '';
    _moveCamera(me!, 15);
    try {
      nearby = await app.client.nearby(app.city, gLat, gLng);
      await app.setLastLocation(gLat, gLng);
    } catch (_) {
      // 站点拉取失败不影响地图展示
    }
    notifyListeners();
  }

  Future<void> _toCityCenter(AppState app, bool silent) async {
    final cached = app.cachedCityCenter(app.city);
    if (cached != null && cached.length == 2) {
      me = LatLng(cached[0], cached[1]);
      hint = silent ? '' : '未授权定位，已显示${app.city}市区；点定位按钮授权后可查附近站点';
      _moveCamera(me!, 12);
      notifyListeners();
      return;
    }
    if (!silent) {
      hint = '正在定位${app.city}市区…';
      notifyListeners();
    }
    try {
      final c = await app.client.cityCenterGuess(app.city);
      if (c != null) {
        app.cacheCityCenter(app.city, c.$1, c.$2);
        me = LatLng(c.$1, c.$2);
        hint = silent ? '' : '未授权定位，已显示${app.city}市区；点定位按钮授权后可查附近站点';
        _moveCamera(me!, 12);
      } else if (!silent) {
        hint = '未能确定${app.city}市区位置，请授权定位';
      }
    } catch (e) {
      if (!silent) hint = '城市定位失败：$e';
    }
    notifyListeners();
  }
}
