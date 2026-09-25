import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/ui.dart';
import '../widgets/line_map.dart';
import '../widgets/line_timeline.dart';
import '../widgets/station_strip.dart';

/// 站牌页：站点各线路（CMD115）→ 选线路进入横滑站牌（CMD103+CMD104 轮询）。
/// 复刻原版 RTimeActivity 的核心视觉。
class StationBoardPage extends StatefulWidget {
  final String stationName;
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

enum _Phase { loading, lines, candidates, board }

class _StationBoardPageState extends State<StationBoardPage> {
  late String _name;
  _Phase _phase = _Phase.loading;
  Object? _error;
  List<StationLine>? _lines;
  List<StationHit>? _candidates;

  StationLine? _selected;
  LineDetail? _detail;
  RealTime? _rt;
  bool _rtLoading = false;
  bool _verticalAxis = false; // 站牌轴纵向（默认横向滑条）
  int _order = 1; // 当前查询站序（纵向时间轴里点站点可切换）
  Timer? _timer;
  String? _lastBoardKey; // 最近打开过的方向（列表里标「当前」）

  @override
  void initState() {
    super.initState();
    _name = widget.stationName;
    _verticalAxis = context.read<AppState>().verticalAxis; // 默认站轴方向
    // 帧后执行: _loadLines 的错误路径会用到 ScaffoldMessenger(inherited),
    // initState 期间同步调用会抛 dependOnInherited 异常
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLines());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadLines() async {
    final app = context.read<AppState>();
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    try {
      final lines = await app.client.stationLines(
        app.city,
        _name,
        lat: widget.lat,
        lng: widget.lng,
      );
      if (!mounted) return;
      if (lines.isEmpty) {
        final cands = await app.client.searchStation(app.city, _name);
        if (!mounted) return;
        _candidates = cands;
        _phase = cands.isEmpty ? _Phase.lines : _Phase.candidates;
      } else {
        _lines = lines;
        _phase = _Phase.lines;
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
        _phase = _Phase.lines;
      });
      showError(context, e);
    }
  }

  Future<void> _openBoard(StationLine l) async {
    final app = context.read<AppState>();
    setState(() {
      _selected = l;
      _order = l.stationOrder;
      _lastBoardKey = '${l.lineName}|${l.upperOrDown}';
      _phase = _Phase.board;
      _rt = null;
    });
    _timer?.cancel();
    try {
      _detail = await app.client.lineStations(
        app.city,
        l.lineName,
        l.upperOrDown,
      );
      if (!mounted) return;
      await _refreshRt();
      _timer = Timer.periodic(
        Duration(seconds: app.refreshSeconds),
        (_) => _refreshRt(silent: true),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _refreshRt({bool silent = false}) async {
    final l = _selected;
    if (l == null) return;
    final app = context.read<AppState>();
    if (!silent) setState(() => _rtLoading = true);
    try {
      final rt = await app.client.realtime(
        app.city,
        l.lineName,
        l.upperOrDown,
        _order,
      );
      if (!mounted) return;
      setState(() => _rt = rt);
    } catch (e) {
      if (!silent && mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _rtLoading = false);
    }
  }

  void _backToLines() {
    _timer?.cancel();
    setState(() {
      _phase = _Phase.lines;
      _selected = null;
      _detail = null;
      _rt = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final fav = SavedItem(type: 'station', city: app.city, name: _name, at: 0);
    return PopScope(
      canPop: _phase != _Phase.board,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase == _Phase.board) _backToLines();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_name),
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
        body: switch (_phase) {
          _Phase.loading => const Center(child: CircularProgressIndicator()),
          _Phase.lines => _linesView(context),
          _Phase.candidates => _candidatesView(context),
          _Phase.board => _boardView(context),
        },
      ),
    );
  }

  Widget _linesView(BuildContext context) {
    if (_error != null) {
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
    final lines = _lines;
    if (lines == null) return const SizedBox.shrink();
    if (lines.isEmpty) return const Center(child: Text('该站暂无线路数据'));
    // 复刻原版「多线路对比」样式：
    // 车号(粗体) + 「当前」橙框徽章 | 右侧橙色状态文字；下行灰色「方向 …」；细分隔线。
    const orange = Color(0xFFF2691B);
    const green = Color(0xFF3CB454);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            '多线路对比',
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
              final statusColor = switch (arrival.state) {
                ArrivalState.arriving => green,
                ArrivalState.noService => orange,
                _ => orange,
              };
              final isCurrent =
                  _lastBoardKey == '${l.lineName}|${l.upperOrDown}';
              return InkWell(
                onTap: () => _openBoard(l),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                          Text(
                            arrival.summary,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '方向 ${l.upperOrDown == '1' ? '上行' : '下行'}'
                        ' · 本站第${l.stationOrder}站',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
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
            '「$_name」未精确命中，以下是候选站：',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        for (final c in cands)
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(c.stationName),
            subtitle: c.sameNameNum > 0 ? Text('同名站 ${c.sameNameNum} 个') : null,
            onTap: () {
              setState(() {
                _name = c.stationName;
                _candidates = null;
              });
              _loadLines();
            },
          ),
      ],
    );
  }

  Widget _boardView(BuildContext context) {
    final l = _selected!;
    final rt = _rt;
    final cs = Theme.of(context).colorScheme;
    final axisToggle = IconButton(
      onPressed: () => setState(() => _verticalAxis = !_verticalAxis),
      icon: Icon(_verticalAxis ? Icons.swap_horiz : Icons.swap_vert),
      tooltip: _verticalAxis ? '横向站牌' : '纵向站轴',
    );
    final header = Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: ListTile(
        leading: IconButton(
          onPressed: _backToLines,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          '${l.lineName} ${l.upperOrDown == '1' ? '上行' : '下行'}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('本站站序 $_order · 点按刷新'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            axisToggle,
            if (_rtLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                onPressed: () => _refreshRt(),
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        onTap: () => _refreshRt(),
      ),
    );
    final mapCard = (context.read<AppState>().mapAlwaysOn && _detail != null)
        ? SizedBox(
            height: 180,
            child: LineMapWidget(
              detail: _detail!,
              rt: _rt,
              selectedOrder: _order,
            ),
          )
        : null;

    if (_verticalAxis) {
      // 纵向站轴: 时间轴占满余下空间, 预测卡固定底部
      return Column(
        children: [
          ?mapCard,
          header,
          Expanded(
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _detail == null
                    ? const Center(child: CircularProgressIndicator())
                    : LineTimeline(
                        detail: _detail!,
                        rt: _rt,
                        selectedOrder: _order,
                        rtLoading: _rtLoading,
                        onSelectStation: (o) {
                          setState(() => _order = o);
                          _refreshRt();
                        },
                      ),
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _predictions(context, rt, cs),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          ?mapCard,
          header,
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _detail == null
                  ? const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : StationStrip(
                      detail: _detail!,
                      rt: _rt,
                      currentOrder: _order,
                      onStationTap: (o) {
                        setState(() => _order = o);
                        _refreshRt();
                      },
                    ),
            ),
          ),
          Card(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _predictions(context, rt, cs),
            ),
          ),
        ],
      ),
    );
  }

  Widget _predictions(BuildContext context, RealTime? rt, ColorScheme cs) {
    if (rt == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rt.stopped) {
      return const Center(
        child: Text('该线路已停运', style: TextStyle(fontSize: 16)),
      );
    }
    if (!rt.hasRealtime) {
      return Center(
        child: Text(
          rt.planTime.isEmpty ? '暂无实时数据' : '非实时时段（计划班次 ${rt.planTime}）',
          style: const TextStyle(fontSize: 15),
        ),
      );
    }
    final preds = rt.predictions.where((p) => p.count >= 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preds.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('暂无车辆接近')),
          )
        else ...[
          Text(
            preds.first.busNumber,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${preds.first.tips} · 约${preds.first.timeTips} · ${preds.first.distTips}',
            style: TextStyle(
              fontSize: 18,
              color: cs.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Divider(height: 20),
          for (final p in preds.skip(1).take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Text(p.busNumber),
                  const Spacer(),
                  Text(
                    '${p.tips} · ${p.timeTips} · ${p.distTips}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '运营中${rt.planTime.isEmpty ? '' : '（计划班次 ${rt.planTime}）'} · ${rt.buses.length}辆车',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
