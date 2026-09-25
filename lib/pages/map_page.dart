import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/geo.dart';
import '../utils/ui.dart';
import 'station_board_page.dart';

/// 地图页：高德栅格瓦片（GCJ-02，无 key）+ 我的位置 + 附近站点。
/// 未授权定位时自动落到所选城市市区（接口站点质心估算）。
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _mapController = MapController();
  LatLng? _me;
  List<NearbyStation>? _nearby;
  bool _locating = false;
  bool _cityCenterUsed = false;
  String _hint = '';
  bool _mapReady = false;
  String _initCity = ''; // 已对准过的城市（切城市后需重新定位）

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCenter());
  }

  /// 确保地图对准当前设置城市：缓存直用，否则估算质心并缓存。
  /// 已授权定位时优先真实定位。城市切换（IndexedStack 常驻本页）会再次触发。
  Future<void> _ensureCenter() async {
    final app = context.read<AppState>();
    if (!app.ready || app.city == _initCity) {
      if (!app.ready) {
        setState(() => _hint = '请先在首页选择城市');
      }
      return;
    }
    _initCity = app.city;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        await _locate();
        return;
      }
    } catch (_) {
      // 桌面端可能无定位插件支持，落到城市中心估算
    }
    final cached = app.cachedCityCenter(app.city);
    if (cached != null && cached.length == 2) {
      if (!mounted) return;
      _me = LatLng(cached[0], cached[1]);
      _cityCenterUsed = true;
      _hint = '未授权定位，已显示${app.city}市区；点右下角按钮授权后可查附近站点';
      _moveMap(_me!, 12);
      setState(() {});
      return;
    }
    setState(() => _hint = '正在定位${app.city}市区…');
    try {
      final c = await app.client.cityCenterGuess(app.city);
      if (!mounted) return;
      if (c != null) {
        app.cacheCityCenter(app.city, c.$1, c.$2);
        _me = LatLng(c.$1, c.$2);
        _cityCenterUsed = true;
        _hint = '未授权定位，已显示${app.city}市区；点右下角按钮授权后可查附近站点';
        _moveMap(_me!, 12);
      } else {
        _hint = '未能确定${app.city}市区位置，请授权定位';
      }
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _hint = '城市定位失败：$e');
    }
  }

  /// 把地图相机移到 [c]。initialCenter 只在创建时生效，之后必须手动 move。
  void _moveMap(LatLng c, double zoom) {
    if (_mapReady) _mapController.move(c, zoom);
  }

  Future<void> _locate() async {
    final app = context.read<AppState>();
    if (!app.ready) {
      _hint = '请先在首页选择城市';
      setState(() {});
      return;
    }
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
      _cityCenterUsed = false;
      _nearby = await app.client.nearby(app.city, gLat, gLng);
      _hint = '';
      _moveMap(_me!, 14);
      await app.setLastLocation(gLat, gLng);
    } catch (e) {
      _hint = e.toString();
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // IndexedStack 常驻本页：城市切换后重新对准新城市
    if (app.city != _initCity) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureCenter();
      });
    }
    return Scaffold(
      appBar: AppBar(title: const Text('地图')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _me ?? const LatLng(24.91, 118.58),
              initialZoom: _me == null ? 11 : 14,
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
              MarkerLayer(markers: _markers(context)),
            ],
          ),
          if (_nearby == null || _cityCenterUsed)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(child: Text(_hint)),
                      FilledButton.tonal(
                        onPressed: app.ready ? _locate : null,
                        child: const Text('定位'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: app.ready ? _locate : null,
        child: _locating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location),
      ),
    );
  }

  List<Marker> _markers(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final markers = <Marker>[];
    if (_me != null) {
      markers.add(
        Marker(
          point: _me!,
          width: 18,
          height: 18,
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
          width: 120,
          height: 34,
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
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: cs.primary),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${s.name} ${s.dis}米',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.4,
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.place, size: 14, color: cs.primary),
              ],
            ),
          ),
        ),
      );
    }
    return markers;
  }
}
