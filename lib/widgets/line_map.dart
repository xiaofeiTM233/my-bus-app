import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';

/// 线路地图：高德栅格瓦片（GCJ-02）+ 轨迹 + 编号站点 + 实时车辆。
class LineMapWidget extends StatelessWidget {
  final LineDetail detail;
  final RealTime? rt;
  final int? selectedOrder;
  const LineMapWidget(
      {super.key, required this.detail, required this.rt, this.selectedOrder});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final track = [
      for (final (la, ln) in detail.track) LatLng(la, ln)
    ];
    final stations = detail.stations
        .where((s) => s.lat != 0 || s.lon != 0)
        .toList();
    final fitCoords = <LatLng>[
      ...track,
      for (final s in stations) LatLng(s.lat, s.lon),
    ];
    final buses = rt?.buses ?? const <BusInfo>[];
    // 拥堵着色：CMD104 speedlist 每项对应一个站间段（station i → i+1），
    // 用站点 niheIndex 把段映射到轨迹点子区间；无数据时整条用主题色。
    final polylines = <Polyline>[];
    if (track.length > 1) {
      polylines.add(Polyline(
          points: track,
          strokeWidth: 5,
          color: cs.primary.withValues(alpha: 0.85)));
      final speedList = rt?.speedList ?? const <SpeedInfo>[];
      final all = detail.stations;
      for (var i = 0;
          i < all.length - 1 && i < speedList.length;
          i++) {
        final c = congestionColor(speedList[i].co);
        if (c == null) continue;
        final a = all[i].niheIndex;
        final b = all[i + 1].niheIndex;
        if (a < 0 || b <= a || b >= track.length) continue;
        polylines.add(Polyline(
          points: track.sublist(a, b + 1),
          strokeWidth: 5,
          color: Color(c),
        ));
      }
    }
    return FlutterMap(
      options: MapOptions(
        initialCenter: fitCoords.isEmpty
            ? const LatLng(24.91, 118.58)
            : fitCoords.first,
        initialZoom: 14,
        maxZoom: 18, // 高德栅格瓦片最大 18 级，超出会加载空白
        initialCameraFit: fitCoords.isEmpty
            ? null
            : CameraFit.coordinates(coordinates: fitCoords, padding: const EdgeInsets.all(48)),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
          subdomains: const ['1', '2', '3', '4'],
          userAgentPackageName: 'com.thirdparty.zsgj.my_bus_app',
          errorTileCallback: (tile, error, stack) {},
        ),
        if (polylines.isNotEmpty)
          PolylineLayer(polylines: polylines),
        MarkerLayer(markers: [
          for (final s in stations)
            Marker(
              point: LatLng(s.lat, s.lon),
              width: 26,
              height: 26,
              alignment: Alignment.topCenter,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selectedOrder == s.order ? cs.primary : Colors.white,
                  border: Border.all(color: cs.primary, width: 2),
                ),
                child: Text('${s.order}',
                    style: TextStyle(
                        fontSize: 10,
                        height: 1,
                        color: selectedOrder == s.order ? Colors.white : cs.primary,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          for (final b in buses)
            if (b.lat != 0 || b.lng != 0)
              Marker(
                point: LatLng(b.lat, b.lng),
                width: 74,
                height: 48,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Transform.rotate(
                    angle: b.angle * math.pi / 180,
                    child: Icon(Icons.navigation,
                        size: 16, color: Colors.deepOrange),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.orange),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(b.busNumber,
                        style: const TextStyle(fontSize: 10, height: 1.3)),
                  ),
                ]),
              ),
        ]),
      ],
    );
  }
}
