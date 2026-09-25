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
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  LatLng? _me;
  List<NearbyStation>? _nearby;
  bool _locating = false;
  String _hint = '点右下角按钮授权定位，查看附近站点';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('地图')),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _me ?? const LatLng(24.91, 118.58),
              initialZoom: _me == null ? 11 : 15,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                subdomains: const ['1', '2', '3', '4'],
                userAgentPackageName: 'com.thirdparty.zsgj.my_bus_app',
                errorTileCallback: (tile, error, stack) {},
              ),
              MarkerLayer(markers: _markers(context)),
            ],
          ),
          if (_nearby == null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(child: Text(_hint)),
                    FilledButton.tonal(
                        onPressed: app.ready ? _locate : null, child: const Text('定位')),
                  ]),
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
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.my_location),
      ),
    );
  }

  List<Marker> _markers(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final markers = <Marker>[];
    if (_me != null) {
      markers.add(Marker(
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
      ));
    }
    for (final s in _nearby ?? const <NearbyStation>[]) {
      markers.add(Marker(
        point: LatLng(s.lat, s.lon),
        width: 120,
        height: 34,
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => StationBoardPage(
                  stationName: s.name,
                  lat: _me?.latitude.toStringAsFixed(6),
                  lng: _me?.longitude.toStringAsFixed(6)))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: cs.primary),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${s.name} ${s.dis}米',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10,
                      height: 1.4,
                      color: cs.primary,
                      fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.place, size: 14, color: cs.primary),
          ]),
        ),
      ));
    }
    return markers;
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
      _nearby = await app.client.nearby(app.city, gLat, gLng);
      _hint = '';
    } catch (e) {
      _hint = e.toString();
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }
}
