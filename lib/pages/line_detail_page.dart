import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/ui.dart';
import '../widgets/line_map.dart';
import '../widgets/line_timeline.dart';
import '../widgets/station_strip.dart';

/// 线路详情：方向切换 + 站点时间轴/地图 + 选中站实时轮询。
class LineDetailPage extends StatefulWidget {
  final String lineName;
  final String dir;
  final int? initialOrder;
  const LineDetailPage({
    super.key,
    required this.lineName,
    required this.dir,
    this.initialOrder,
  });

  @override
  State<LineDetailPage> createState() => _LineDetailPageState();
}

class _LineDetailPageState extends State<LineDetailPage> {
  late String _dir;
  LineDetail? _detail;
  bool _loading = true;
  Object? _error;
  int? _selectedOrder;
  RealTime? _rt;
  bool _rtLoading = false;
  bool _mapView = false;
  bool _horizontalAxis = false; // 站点轴横向（默认纵向时间轴）
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _dir = widget.dir;
    // 默认站轴方向跟随设置：横向→站序条，纵向→时间轴
    _horizontalAxis = !context.read<AppState>().verticalAxis;
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  AppState get _app => context.read<AppState>();

  Future<void> _load() async {
    final app = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await app.client.lineStations(app.city, widget.lineName, _dir);
      if (!mounted) return;
      _detail = d;
      app.addHistory(
        SavedItem(
          type: 'line',
          city: app.city,
          name: widget.lineName,
          dir: _dir,
          subtitle: d.stations.isEmpty ? null : '开往${d.stations.last.showName}',
          at: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (widget.initialOrder != null && _selectedOrder == null) {
        _selectStation(widget.initialOrder!, refresh: false);
        await _fetchRt();
      }
    } catch (e) {
      if (!mounted) return;
      _error = e;
      showError(context, e);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _selectStation(int order, {bool refresh = true}) {
    setState(() => _selectedOrder = order);
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: _app.refreshSeconds),
      (_) => _fetchRt(silent: true),
    );
    if (refresh) _fetchRt();
  }

  Future<void> _fetchRt({bool silent = false}) async {
    final order = _selectedOrder;
    if (order == null) return;
    final app = context.read<AppState>();
    if (!silent) setState(() => _rtLoading = true);
    try {
      final rt = await app.client.realtime(
        app.city,
        widget.lineName,
        _dir,
        order,
      );
      if (!mounted) return;
      setState(() => _rt = rt);
    } catch (e) {
      if (!silent && mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _rtLoading = false);
    }
  }

  void _switchDir(String d) {
    if (d == _dir) return;
    _timer?.cancel();
    setState(() {
      _dir = d;
      _selectedOrder = null;
      _rt = null;
      _detail = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final fav = SavedItem(
      type: 'line',
      city: app.city,
      name: widget.lineName,
      dir: _dir,
      at: 0,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lineName),
        actions: [
          IconButton(
            onPressed: _selectedOrder == null ? null : _fetchRt,
            tooltip: '手动刷新',
            icon: _rtLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => app.toggleFavorite(
              SavedItem(
                type: 'line',
                city: app.city,
                name: widget.lineName,
                dir: _dir,
                subtitle: _detail == null || _detail!.stations.isEmpty
                    ? null
                    : '开往${_detail!.stations.last.showName}',
                at: DateTime.now().millisecondsSinceEpoch,
              ),
            ),
            icon: Icon(app.isFavorite(fav) ? Icons.star : Icons.star_border),
            tooltip: '收藏本方向',
          ),
          IconButton(
            onPressed: _mapView
                ? null
                : () => setState(() => _horizontalAxis = !_horizontalAxis),
            icon: Icon(_horizontalAxis ? Icons.swap_vert : Icons.swap_horiz),
            tooltip: _mapView ? '时间轴' : (_horizontalAxis ? '纵向站轴' : '横向站轴'),
          ),
          IconButton(
            onPressed: () => setState(() => _mapView = !_mapView),
            icon: Icon(_mapView ? Icons.view_list : Icons.map_outlined),
            tooltip: _mapView ? '时间轴' : '地图',
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final app = context.watch<AppState>();
    if (_loading) return _loadingView();
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$_error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final d = _detail!;
    return Column(
      children: [
        if (app.mapAlwaysOn)
          SizedBox(
            height: 200,
            child: LineMapWidget(
              detail: d,
              rt: _rt,
              selectedOrder: _selectedOrder,
            ),
          ),
        _headerCard(context, d),
        if (_selectedOrder != null) _predictionCard(context),
        Expanded(
          child: _mapView
              ? LineMapWidget(detail: d, rt: _rt, selectedOrder: _selectedOrder)
              : _horizontalAxis
              ? Card(
                  margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: StationStrip(
                    detail: d,
                    rt: _rt,
                    currentOrder: _selectedOrder ?? 1,
                    onStationTap: _selectStation,
                  ),
                )
              : LineTimeline(
                  detail: d,
                  rt: _rt,
                  selectedOrder: _selectedOrder,
                  onSelectStation: _selectStation,
                  rtLoading: _rtLoading,
                ),
        ),
      ],
    );
  }

  Widget _loadingView() => const Center(child: CircularProgressIndicator());

  Widget _headerCard(BuildContext context, LineDetail d) {
    final fl = d.firstLast.isEmpty ? null : d.firstLast.first;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '1', label: Text('上行')),
                ButtonSegment(value: '2', label: Text('下行')),
              ],
              selected: {_dir},
              onSelectionChanged: (s) => _switchDir(s.first),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${d.stations.isEmpty ? '' : '始发 ${d.stations.first.showName}'}'
                    '${d.stations.isEmpty ? '' : ' → 终到 ${d.stations.last.showName}'}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Text(
                  '首班 ${fl?.first ?? '--'} · 末班 ${fl?.last ?? '--'} · 共${d.stations.length}站',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _predictionCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rt = _rt;
    final station = _detail!.stations
        .where((s) => s.order == _selectedOrder)
        .toList()
        .lastOrNull;
    String stateText;
    if (rt == null) {
      stateText = _rtLoading ? '加载中…' : '';
    } else if (rt.stopped) {
      stateText = '停运';
    } else if (!rt.hasRealtime) {
      stateText = '暂无实时数据${rt.planTime.isEmpty ? '' : '（计划班次 ${rt.planTime}）'}';
    } else {
      stateText = '运营中${rt.planTime.isEmpty ? '' : '（计划班次 ${rt.planTime}）'}';
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '到站预测 · ${station == null ? '' : stationNameHorizontal(station.showName)}(站序$_selectedOrder)',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (_rtLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                const SizedBox(width: 6),
                Text(stateText, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            if (rt != null && rt.predictions.isNotEmpty)
              ...rt.predictions
                  .take(3)
                  .map(
                    (p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Text(
                            p.busNumber,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${p.tips} · ${p.timeTips} · ${p.distTips}',
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
            else if (rt != null)
              const Text('暂无到站预测', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
