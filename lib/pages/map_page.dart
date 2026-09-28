import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../state/map_store.dart';
import 'station_board_page.dart';

/// 地图页：高德栅格瓦片（GCJ-02，无 key）+ 我的位置 + 附近站点。
/// 与首页常驻小地图共享 MapStore（位置/站点/相机），同一张图。
/// 未授权定位时自动落到所选城市市区（接口站点质心估算）。
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _mapController = MapController();
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCity());
  }

  void _ensureCity() {
    final app = context.read<AppState>();
    if (!app.ready) return;
    context.read<MapStore>().ensureCity(app, silent: false);
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
    final app = context.watch<AppState>();
    final store = context.watch<MapStore>();
    // IndexedStack 常驻本页：城市切换后重新对准新城市
    if (app.ready && app.city != store.locatedCity) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureCity();
      });
    }
    if (_mapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncCamera());
    }
    if (!app.ready && store.hint.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<MapStore>().showHint('请先在首页选择城市');
      });
    }
    return Scaffold(
      appBar: AppBar(title: const Text('地图')),
      body: Stack(
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
              MarkerLayer(markers: _markers(context, store)),
            ],
          ),
          if (store.hint.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(child: Text(store.hint)),
                      FilledButton.tonal(
                        onPressed:
                            app.ready ? () => context.read<MapStore>().locate(app) : null,
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
        onPressed: app.ready ? () => context.read<MapStore>().locate(app) : null,
        child: store.locating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location),
      ),
    );
  }

  List<Marker> _markers(BuildContext context, MapStore store) {
    final cs = Theme.of(context).colorScheme;
    final markers = <Marker>[];
    if (store.me != null) {
      markers.add(
        Marker(
          point: store.me!,
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
    for (final s in store.nearby ?? const <NearbyStation>[]) {
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
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: cs.primary),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${stationNameHorizontal(s.name)} ${s.dis}米',
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
