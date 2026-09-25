import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/geo.dart';
import '../pages/station_board_page.dart';

/// 首页顶部常驻地图（设置里开启）：我的位置 + 附近站点，点站点直达站牌页。
/// 仅在定位权限已授予时自动定位，不主动弹权限框。
class MapBanner extends StatefulWidget {
  final double height;
  const MapBanner({super.key, this.height = 170});

  @override
  State<MapBanner> createState() => _MapBannerState();
}

class _MapBannerState extends State<MapBanner> {
  final _mapController = MapController();
  LatLng? _me;
  List<NearbyStation>? _nearby;
  bool _locating = false;
  bool _mapReady = false;
  String _initCity = ''; // 已对准过的城市（切城市后重新定位）

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoLocate());
  }

  /// 确保地图对准当前城市：已授权→真实定位；否则城市中心（缓存→估算）。
  /// initialCenter 只在地图创建时生效，之后必须用 MapController.move。
  Future<void> _autoLocate() async {
    if (_locating) return;
    final app = context.read<AppState>();
    if (!app.ready) return;
    final changed = app.city != _initCity;
    if (!changed && _me != null) return;
    _initCity = app.city;
    _nearby = null;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        await _locate();
        return;
      }
    } catch (_) {
      // 桌面端无定位支持时落到城市中心
    }
    // 无权限：缓存命中直用，否则估算质心（与地图页共用缓存）
    final cached = app.cachedCityCenter(app.city);
    if (cached != null && cached.length == 2) {
      if (!mounted) return;
      setState(() => _me = LatLng(cached[0], cached[1]));
      _moveMap(_me!, 12);
      return;
    }
    try {
      final c = await app.client.cityCenterGuess(app.city);
      if (!mounted || c == null) return;
      app.cacheCityCenter(app.city, c.$1, c.$2);
      setState(() => _me = LatLng(c.$1, c.$2));
      _moveMap(_me!, 12);
    } catch (_) {
      // 常驻地图是锦上添花，失败静默，不打扰首页
    }
  }

  void _moveMap(LatLng c, double zoom) {
    if (_mapReady) _mapController.move(c, zoom);
  }

  AppState get app => context.read<AppState>();

  Future<void> _locate() async {
    final app = context.read<AppState>();
    if (!app.ready) return;
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw '定位权限被拒绝';
      }
      final pos = await Geolocator.getCurrentPosition();
      final (gLat, gLng) = wgs2gcj(pos.latitude, pos.longitude);
      _me = LatLng(gLat, gLng);
      _nearby = await app.client.nearby(app.city, gLat, gLng);
      _moveMap(_me!, 15);
      app.setLastLocation(gLat, gLng);
    } catch (_) {
      // 常驻地图是锦上添花，失败静默，不打扰首页
      // 真实定位失败也要保证地图对准所选城市
      final cached = app.cachedCityCenter(app.city);
      if (cached != null && cached.length == 2) {
        _me = LatLng(cached[0], cached[1]);
        _moveMap(_me!, 12);
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final app = context.watch<AppState>();
    // IndexedStack 常驻本组件：城市切换后重新对准
    if (app.city != _initCity) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoLocate();
      });
    }
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _me ?? const LatLng(24.91, 118.58),
              initialZoom: _me == null ? 11 : 15,
              onMapReady: () {
                _mapReady = true;
                if (_me != null) _mapController.move(_me!, 12);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                subdomains: const ['1', '2', '3', '4'],
                userAgentPackageName: 'com.thirdparty.zsgj.my_bus_app',
                errorTileCallback: (tile, error, stack) {},
              ),
              MarkerLayer(markers: _markers(cs)),
            ],
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: SizedBox(
              width: 34,
              height: 34,
              child: FloatingActionButton(
                heroTag: 'map-banner-locate',
                onPressed: _locate,
                child: _locating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Marker> _markers(ColorScheme cs) {
    final markers = <Marker>[];
    if (_me != null) {
      markers.add(
        Marker(
          point: _me!,
          width: 16,
          height: 16,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      );
    }
    for (final s in _nearby ?? const <NearbyStation>[]) {
      markers.add(
        Marker(
          point: LatLng(s.lat, s.lon),
          width: 110,
          height: 30,
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StationBoardPage(
                  stationName: s.name,
                  lat: _me?.latitude.toStringAsFixed(6),
                  lng: _me?.longitude.toStringAsFixed(6),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: cs.primary),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '${s.name} ${s.dis}米',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.4,
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.place, size: 12, color: cs.primary),
              ],
            ),
          ),
        ),
      );
    }
    return markers;
  }
}
