import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../pages/station_board_page.dart';
import '../state/app_state.dart';
import '../state/map_store.dart';

/// 首页顶部常驻地图（设置里开启）。
/// 与地图页共享 MapStore（位置/站点/相机），切到全屏地图是同一张图。
/// 仅在定位权限已授予时自动定位，不主动弹权限框。
class MapBanner extends StatefulWidget {
  final double height;
  const MapBanner({super.key, this.height = 170});

  @override
  State<MapBanner> createState() => _MapBannerState();
}

class _MapBannerState extends State<MapBanner> {
  final _mapController = MapController();
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCity());
  }

  void _ensureCity() {
    final app = context.read<AppState>();
    if (app.ready) {
      context.read<MapStore>().ensureCity(app, silent: true);
    }
  }

  /// 相机同步：共享相机与本图偏差明显时对齐（另一张地图拖动后）。
  void _syncCamera() {
    if (!_mapReady) return;
    final store = context.read<MapStore>();
    final c = store.camCenter;
    if (c == null) return;
    final cam = _mapController.camera;
    if ((cam.center.latitude - c.latitude).abs() > 1e-9 ||
        (cam.center.longitude - c.longitude).abs() > 1e-9 ||
        (cam.zoom - store.camZoom).abs() > 1e-9) {
      _mapController.move(c, store.camZoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final app = context.watch<AppState>();
    final store = context.watch<MapStore>();
    // IndexedStack 常驻本组件：城市切换后重新对准
    if (app.ready && app.city != store.locatedCity) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureCity();
      });
    }
    if (_mapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncCamera());
    }
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: store.camCenter ?? MapStore.defaultCenter,
              initialZoom: store.camZoom,
              onMapReady: () {
                _mapReady = true;
                _syncCamera();
              },
              onPositionChanged: (pos, hasGesture) {
                // 本图手势 → 记入共享相机（不 notify，对侧地图稍后对齐）
                if (hasGesture) {
                  store.reportCamera(pos.center, pos.zoom);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                subdomains: const ['1', '2', '3', '4'],
                userAgentPackageName: 'com.thirdparty.zsgj.my_bus_app',
                errorTileCallback: (tile, error, stack) {},
              ),
              MarkerLayer(markers: _markers(cs, store)),
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
                onPressed: () =>
                    context.read<MapStore>().locate(context.read<AppState>()),
                child: store.locating
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

  List<Marker> _markers(ColorScheme cs, MapStore store) {
    final markers = <Marker>[];
    if (store.me != null) {
      markers.add(
        Marker(
          point: store.me!,
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
    for (final s in store.nearby ?? const <NearbyStation>[]) {
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
                  // 传站点自身坐标（CMD115 按 MY 坐标就近匹配，用户定位可能偏差过大）
                  lat: s.lat.toStringAsFixed(6),
                  lng: s.lon.toStringAsFixed(6),
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
                    '${stationNameHorizontal(s.name)} ${s.dis}米',
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
