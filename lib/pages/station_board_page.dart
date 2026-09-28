import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../state/map_store.dart';
import '../utils/geo.dart';
import '../utils/ui.dart';
import 'line_detail_page.dart';

/// 站牌页（参考原版「站点地图」）：
/// 地图 + 站名卡片（反向站台换向）+ 全部经过线路对比。
/// 选线路进入路线页（复用线路模块，定位到本站站序）。
/// 导航（到这里去/从这出发）暂未实现，入口置灰占位。
class StationBoardPage extends StatefulWidget {
  final String stationName;

  /// 站台坐标（用于 CMD115 精确匹配与反向站台查找）
  final String? lat;
  final String? lng;
  const StationBoardPage({
    super.key,
    required this.stationName,
    this.lat,
    this.lng,
  });

  @override
  State<StationBoardPage> createState() => _StationBoardPageState();
}

class _StationBoardPageState extends State<StationBoardPage> {
  late String _name;

  /// 当前站台坐标（反向站台换向后更新）
  double? _lat;
  double? _lng;
  bool _reversing = false;

  bool _loading = true;
  Object? _error;
  List<StationLine>? _lines;
  List<StationHit>? _candidates;

  /// 同名/反向站台列表（CMD209，含当前站台）；null = 未获取或获取失败
  List<NearbyStation>? _platforms;
  String? _lastBoardKey; // 最近打开过的方向（列表里标「当前」）

  @override
  void initState() {
    super.initState();
    _name = widget.stationName;
    _lat = double.tryParse(widget.lat ?? '');
    _lng = double.tryParse(widget.lng ?? '');
    // 帧后执行: _loadLines 的错误路径会用到 ScaffoldMessenger(inherited),
    // initState 期间同步调用会抛 dependOnInherited 异常
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLines());
  }

  Future<void> _loadLines() async {
    final app = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var lines = await app.client.stationLines(
        app.city,
        _name,
        lat: _lat?.toStringAsFixed(6),
        lng: _lng?.toStringAsFixed(6),
        all: true, // ALL=1：全部经过线路；ALL=0 只返回有实时数据的一小部分
      );
      // CMD115 按 MY 坐标就近匹配同名站，坐标偏差过大时返回空——去坐标重试
      if (lines.isEmpty && (_lat != null || _lng != null)) {
        lines = await app.client.stationLines(app.city, _name, all: true);
      }
      if (!mounted) return;
      if (lines.isEmpty) {
        final cands = await app.client.searchStation(app.city, _name);
        if (!mounted) return;
        _candidates = cands;
        _lines = null;
        if (cands.isEmpty) _lines = [];
      } else {
        _lines = lines;
        _candidates = null;
      }
      // 同名/反向站台列表（CMD209，原版站牌页加载时同样拉取）；失败不影响主流程
      _platforms = null;
      if (_name.isNotEmpty) {
        try {
          _platforms = await app.client.stationPlatforms(
            app.city,
            _name,
            myLat: _lat?.toStringAsFixed(6),
            myLng: _lng?.toStringAsFixed(6),
            lat: _lat?.toStringAsFixed(6),
            lng: _lng?.toStringAsFixed(6),
          );
        } catch (_) {}
        if (!mounted) return;
      }
      app.addHistory(
        SavedItem(
          type: 'station',
          city: app.city,
          name: _name,
          at: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _lines = null;
        _candidates = null;
      });
      showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 反向/切换站台（原版 stationChange 逻辑）：CMD209 已缓存的站台数组内
  /// 循环取下一个不同坐标的站台（零额外请求），再以新站台坐标重查 CMD115。
  Future<void> _reversePlatform() async {
    final platforms = _platforms;
    if (platforms == null || platforms.length < 2) return;
    final lat = _lat;
    final lng = _lng;
    // 当前站台 = 距现有坐标最近的条目（同名站台可能仅相距几十米，
    // 不能用「<50 米即当前」判断，否则双向都会命中）
    var cur = 0;
    var best = double.infinity;
    for (var i = 0; i < platforms.length; i++) {
      final p = platforms[i];
      final d = (lat == null || lng == null)
          ? 0.0
          : distMeters(lat, lng, p.lat, p.lon);
      if (d < best) {
        best = d;
        cur = i;
      }
    }
    final next = platforms[(cur + 1) % platforms.length];
    setState(() => _reversing = true);
    try {
      setState(() {
        _lat = next.lat;
        _lng = next.lon;
      });
      await _loadLines();
    } finally {
      if (mounted) setState(() => _reversing = false);
    }
  }

  /// 选线路 → 路线页（定位到本站站序，进入该站实时轮询）。
  void _openLine(StationLine l) {
    setState(() => _lastBoardKey = '${l.lineName}|${l.upperOrDown}');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LineDetailPage(
          lineName: l.lineName,
          dir: l.upperOrDown,
          initialOrder: l.stationOrder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final store = context.watch<MapStore>();
    final fav = SavedItem(type: 'station', city: app.city, name: _name, at: 0);
    return Scaffold(
      appBar: AppBar(
        // 显示用横排括号（︵︶ → （）），请求仍用原始名 _name
        title: Text(stationNameHorizontal(_name)),
        actions: [
          IconButton(
            onPressed: () => app.toggleFavorite(
              SavedItem(
                type: 'station',
                city: app.city,
                name: _name,
                subtitle: _lines == null ? null : '${_lines!.length}条线路',
                at: DateTime.now().millisecondsSinceEpoch,
              ),
            ),
            icon: Icon(app.isFavorite(fav) ? Icons.star : Icons.star_border),
            tooltip: '收藏本站',
          ),
          IconButton(onPressed: _loadLines, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _retryView(context)
              : _candidates != null
                  ? _candidatesView(context)
                  : Column(
                      children: [
                        ?_stationMap(context, store),
                        _headerCard(context),
                        Expanded(child: _linesView(context)),
                      ],
                    ),
    );
  }

  Widget _retryView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$_error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: _loadLines, child: const Text('重试')),
        ],
      ),
    );
  }

  /// 站点位置小地图：站点标记 + 我的位置 + 全屏查看入口。
  Widget? _stationMap(BuildContext context, MapStore store) {
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null) return null;
    final cs = Theme.of(context).colorScheme;
    final station = LatLng(lat, lng);
    final markers = _stationMarkers(cs, store, station);
    return SizedBox(
      height: 200,
      child: Stack(
        children: [
          FlutterMap(
            // 高德栅格瓦片最大 18 级，超出会加载空白
            options: MapOptions(
                initialCenter: station, initialZoom: 15, maxZoom: 18),
            children: [
              TileLayer(
                urlTemplate:
                    'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                subdomains: const ['1', '2', '3', '4'],
                userAgentPackageName: 'com.thirdparty.zsgj.my_bus_app',
                errorTileCallback: (tile, error, stack) {},
              ),
              MarkerLayer(markers: markers),
            ],
          ),
          // 全屏查看
          Positioned(
            top: 6,
            right: 6,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _showFullMap(context, station, markers),
                child: const Padding(
                  padding: EdgeInsets.all(7),
                  child:
                      Icon(Icons.open_in_full, size: 16, color: Colors.black87),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Marker> _stationMarkers(
      ColorScheme cs, MapStore store, LatLng station) {
    return [
      // 我的位置
      if (store.me != null)
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
      // 站点
      Marker(
        point: station,
        width: 30,
        height: 30,
        alignment: Alignment.topCenter,
        child:
            Icon(Icons.location_on_rounded, size: 30, color: cs.primary),
      ),
    ];
  }

  /// 全屏地图：可自由缩放拖动（与站牌页地图共用标记）。
  void _showFullMap(
      BuildContext context, LatLng station, List<Marker> markers) {
    showDialog(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                  initialCenter: station, initialZoom: 16, maxZoom: 18),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                  subdomains: const ['1', '2', '3', '4'],
                  userAgentPackageName: 'com.thirdparty.zsgj.my_bus_app',
                  errorTileCallback: (tile, error, stack) {},
                ),
                MarkerLayer(markers: markers),
              ],
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 站名卡片 + 操作 chips（参考原版：反向站台 / 到这里去 / 从这出发）。
  Widget _headerCard(BuildContext context) {
    const orange = Color(0xFFF2691B);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.directions_bus_outlined,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stationNameHorizontal(_name),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                if (_platforms != null && _platforms!.length > 1)
                  Text('${_platforms!.length} 个同名站台',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  avatar: _reversing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.swap_horiz, size: 18),
                  // 原版语义：同名站台=2 显示「反向站台」，更多显示「切换站台」
                  label: Text(
                      _platforms != null && _platforms!.length > 2
                          ? '切换站台'
                          : '反向站台',
                      style: const TextStyle(
                          color: orange, fontWeight: FontWeight.w600)),
                  side: const BorderSide(color: orange),
                  onPressed:
                      (_platforms != null && _platforms!.length > 1 && !_reversing)
                          ? _reversePlatform
                          : null,
                ),
                const Tooltip(
                  message: '导航功能开发中',
                  child: ActionChip(
                    avatar: Icon(Icons.near_me_outlined, size: 18),
                    label: Text('到这里去'),
                    onPressed: null,
                  ),
                ),
                const Tooltip(
                  message: '导航功能开发中',
                  child: ActionChip(
                    avatar: Icon(Icons.trip_origin, size: 18),
                    label: Text('从这出发'),
                    onPressed: null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _linesView(BuildContext context) {
    final lines = _lines;
    if (lines == null) return const SizedBox.shrink();
    if (lines.isEmpty) return const Center(child: Text('该站暂无线路数据'));
    const orange = Color(0xFFF2691B);
    const green = Color(0xFF3CB454);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '经过本站的线路（点按查看实时车辆）',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: lines.length,
            separatorBuilder: (_, _) => const Divider(
              height: 1,
              thickness: 0.5,
              indent: 16,
              endIndent: 16,
            ),
            itemBuilder: (_, i) {
              final l = lines[i];
              final arrival = arrivalOf(l);
              // 右侧两行：状态（即将到站/N站/等待发车…）+ 时间/距离
              final (String primary, Color statusColor, String secondary) =
                  switch (arrival.state) {
                ArrivalState.arriving => (
                    arrival.raw.isEmpty ? '即将到站' : arrival.raw,
                    green,
                    '',
                  ),
                ArrivalState.approaching => (
                    arrival.stationsAway != null
                        ? '${arrival.stationsAway}站'
                        : (arrival.raw.isEmpty ? '即将到站' : arrival.raw),
                    orange,
                    [
                      if (l.nearTime.isNotEmpty) l.nearTime,
                      if (l.nearDis.isNotEmpty) l.nearDis,
                    ].join(' / '),
                  ),
                ArrivalState.noService => (
                    arrival.raw.isEmpty ? '暂无车辆' : arrival.raw,
                    orange,
                    '',
                  ),
                ArrivalState.unknown => ('—', Colors.grey, ''),
              };
              final isCurrent =
                  _lastBoardKey == '${l.lineName}|${l.upperOrDown}';
              return ListTile(
                onTap: () => _openLine(l),
                title: Row(
                  children: [
                    Text(
                      l.lineName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: orange),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '当前',
                          style: TextStyle(fontSize: 11, color: orange),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          primary,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                        if (secondary.isNotEmpty)
                          Text(
                            secondary,
                            style:
                                const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                  ],
                ),
                subtitle: Text(
                  '方向 ${l.upperOrDown == '1' ? '上行' : '下行'} · 本站第${l.stationOrder}站',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _candidatesView(BuildContext context) {
    final cands = _candidates ?? const <StationHit>[];
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '「${stationNameHorizontal(_name)}」未精确命中，以下是候选站：',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        for (final c in cands)
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(stationNameHorizontal(c.stationName)),
            subtitle: c.sameNameNum > 0 ? Text('同名站 ${c.sameNameNum} 个') : null,
            onTap: () {
              setState(() {
                _name = c.stationName;
                _candidates = null;
                _lat = null;
                _lng = null;
              });
              _loadLines();
            },
          ),
      ],
    );
  }
}
