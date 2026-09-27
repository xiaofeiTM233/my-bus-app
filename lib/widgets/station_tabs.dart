import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/geo.dart';
import '../utils/ui.dart';
import '../pages/line_detail_page.dart';
import '../pages/station_board_page.dart';

/// 首页中部子 Tab：附近 / 最近 / 收藏。
class StationTabs extends StatelessWidget {
  const StationTabs({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        TabBar(
          tabs: const [Tab(text: '附近'), Tab(text: '最近'), Tab(text: '收藏')],
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Theme.of(context).colorScheme.outline,
        ),
        Expanded(
          child: TabBarView(children: [
            const NearbyPanel(),
            const RecentPanel(),
            const FavoritesPanel(),
          ]),
        ),
      ]),
    );
  }
}

void _openStation(BuildContext context, String name, {String? lat, String? lng}) {
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          StationBoardPage(stationName: name, lat: lat, lng: lng)));
}

void _openLine(BuildContext context, SavedItem item) {
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LineDetailPage(
          lineName: item.name, dir: item.dir ?? '1', initialOrder: item.order)));
}

// ─── 附近 ───

class NearbyPanel extends StatefulWidget {
  const NearbyPanel({super.key});

  @override
  State<NearbyPanel> createState() => _NearbyPanelState();
}

class _NearbyPanelState extends State<NearbyPanel> {
  bool _loading = false;
  bool _locating = false;
  bool _autoTried = false;
  String? _error;
  String? _locStatus;
  double? _lat;
  double? _lng;
  List<NearbyStation>? _stations;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoLocate());
  }

  /// 首次进入时，若定位权限已授予则自动定位（不主动弹权限框）。
  Future<void> _autoLocate() async {
    if (_autoTried) return;
    _autoTried = true;
    final app = context.read<AppState>();
    if (!app.ready) return;
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
      await _locate();
    }
  }

  Future<void> _locate() async {
    final app = context.read<AppState>();
    if (!app.ready) {
      showError(context, '请先选择城市');
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
        throw '定位权限被拒绝，请检查系统权限设置';
      }
      final pos = await Geolocator.getCurrentPosition();
      final (gLat, gLng) = wgs2gcj(pos.latitude, pos.longitude);
      _lat = gLat;
      _lng = gLng;
      _locStatus = '已定位 ${gLat.toStringAsFixed(4)}, ${gLng.toStringAsFixed(4)}';
      await _query();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _manualDialog() async {
    final latC = TextEditingController(text: _lat?.toStringAsFixed(6));
    final lngC = TextEditingController(text: _lng?.toStringAsFixed(6));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动输入坐标（GCJ-02）'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: latC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'LAT 纬度')),
          TextField(
              controller: lngC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'LNG 经度')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _lat = double.tryParse(latC.text.trim());
    _lng = double.tryParse(lngC.text.trim());
    if (_lat == null || _lng == null) {
      showError(context, '坐标格式不正确');
      return;
    }
    _locStatus = '手动坐标 ${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}';
    await _query();
  }

  Future<void> _query() async {
    final app = context.read<AppState>();
    if (_lat == null || _lng == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _stations = await app.client.nearby(app.city, _lat!, _lng!);
    } catch (e) {
      _error = e.toString();
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 2),
        child: Row(children: [
          Expanded(
            child: Text(
              app.city.isEmpty
                  ? '请先选择城市'
                  : (_locStatus ?? '点 📍 授权定位，查看附近站点'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_locating)
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            IconButton(
                tooltip: '定位',
                onPressed: app.ready ? _locate : null,
                icon: const Icon(Icons.my_location)),
            IconButton(
                tooltip: '手动输入坐标',
                onPressed: app.ready ? _manualDialog : null,
                icon: const Icon(Icons.edit_location_alt_outlined)),
          ],
        ]),
      ),
      Expanded(child: _buildList(context, app)),
    ]);
  }

  Widget _buildList(BuildContext context, AppState app) {
    if (!app.ready) return const Center(child: Text('请先选择城市'));
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }
    final sts = _stations;
    if (sts == null) {
      return const Center(child: Text('点 📍 授权定位后显示附近站点'));
    }
    if (sts.isEmpty) return const Center(child: Text('附近没有站点'));
    return RefreshIndicator(
      onRefresh: _query,
      child: ListView.builder(
        itemCount: sts.length,
        itemBuilder: (_, i) {
          final s = sts[i];
          return ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(stationNameHorizontal(s.name)),
            subtitle: s.sameNum > 0 ? Text('同名站 ${s.sameNum} 个') : null,
            trailing: Text('${s.dis}米',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600)),
            // 传站点自身坐标：CMD115 按 MY 坐标就近匹配站名，有效半径很小，
            // 传用户定位（漂移/较远）会导致查不到线路
            onTap: () => _openStation(context, s.name,
                lat: s.lat.toStringAsFixed(6), lng: s.lon.toStringAsFixed(6)),
          );
        },
      ),
    );
  }
}

// ─── 最近 ───

class RecentPanel extends StatelessWidget {
  const RecentPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.history.isEmpty) {
      return const Center(child: Text('查过的线路和站点会出现在这里'));
    }
    return ListView.builder(
      itemCount: app.history.length,
      itemBuilder: (_, i) {
        final item = app.history[i];
        final dt = DateTime.fromMillisecondsSinceEpoch(item.at);
        return ListTile(
          leading: Icon(item.type == 'line'
              ? Icons.directions_bus_outlined
              : Icons.place_outlined),
          title: Text(stationNameHorizontal(item.name)),
          subtitle: Text(
              '${item.subtitle ?? (item.type == 'line' ? (item.dir == '1' ? '上行' : '下行') : '站点')}'
              ' · ${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}'),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => app.removeHistory(item),
          ),
          onTap: () {
            app.addHistory(SavedItem(
                type: item.type,
                city: item.city,
                name: item.name,
                dir: item.dir,
                order: item.order,
                subtitle: item.subtitle,
                at: DateTime.now().millisecondsSinceEpoch));
            if (item.type == 'line') {
              _openLine(context, item);
            } else {
              _openStation(context, item.name);
            }
          },
        );
      },
    );
  }
}

// ─── 收藏 ───

class FavoritesPanel extends StatelessWidget {
  const FavoritesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.favorites.isEmpty) {
      return const Center(child: Text('在线路/站牌页点 ☆ 收藏'));
    }
    final lines = app.favorites.where((e) => e.type == 'line').toList();
    final stations = app.favorites.where((e) => e.type == 'station').toList();
    return ListView(children: [
      if (lines.isNotEmpty) _header(context, '线路'),
      for (final item in lines)
        Dismissible(
          key: ValueKey('fav-${item.key}'),
          background: Container(color: Colors.red),
          onDismissed: (_) => app.removeFavorite(item),
          child: ListTile(
            leading: const Icon(Icons.directions_bus_outlined),
            title: Text(stationNameHorizontal(item.name)),
            subtitle: Text(item.subtitle ?? (item.dir == '1' ? '上行' : '下行')),
            onTap: () => _openLine(context, item),
          ),
        ),
      if (stations.isNotEmpty) _header(context, '站点'),
      for (final item in stations)
        Dismissible(
          key: ValueKey('fav-${item.key}'),
          background: Container(color: Colors.red),
          onDismissed: (_) => app.removeFavorite(item),
          child: ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(stationNameHorizontal(item.name)),
            subtitle: item.subtitle == null ? null : Text(item.subtitle!),
            onTap: () => _openStation(context, item.name),
          ),
        ),
    ]);
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary)),
      );
}
