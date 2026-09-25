import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/ui.dart';
import 'line_detail_page.dart';
import 'station_board_page.dart';

/// 搜索页：线路 / 站点 双模式，输入即搜（latest-wins：执行中时新关键词覆盖排队旧词，
/// 响应按序号丢弃过期结果）。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  int _seq = 0; // 递增序号，响应返回时序号不一致则丢弃
  int _mode = 0; // 0=线路 1=站点
  bool _loading = false;
  bool _running = false; // 已有一个搜索在执行/排队
  String? _queuedKw; // 排队中的最新关键词（永远只保留一个）
  String? _error;
  List<LineSummary>? _lines;
  List<StationHit>? _stations;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 输入即搜：立即触发；执行中时新关键词覆盖排队中的旧关键词（latest-wins）。
  void _onChanged(String v) {
    final kw = v.trim();
    setState(() {}); // 刷新清除按钮可见性
    if (kw.isEmpty) {
      _seq++;
      _queuedKw = null;
      _lines = null;
      _stations = null;
      _error = null;
      _loading = false;
      return;
    }
    _requestSearch(kw);
  }

  void _requestSearch(String kw) {
    final seq = ++_seq;
    _maybeRun(kw, seq);
  }

  Future<void> _maybeRun(String kw, int seq) async {
    if (_running) {
      _queuedKw = kw;
      return;
    }
    _running = true;
    try {
      await _search(kw, seq);
    } finally {
      _running = false;
    }
    final next = _queuedKw;
    _queuedKw = null;
    if (next != null) _requestSearch(next);
  }

  Future<void> _search(String kw, int seq) async {
    final app = context.read<AppState>();
    setState(() => _loading = true);
    try {
      if (_mode == 0) {
        final r = await app.client.searchLine(app.city, kw);
        if (seq != _seq || !mounted) return;
        _lines = r;
        _stations = null;
      } else {
        final r = await app.client.searchStation(app.city, kw);
        if (seq != _seq || !mounted) return;
        _stations = r;
        _lines = null;
      }
    } catch (e) {
      if (seq != _seq || !mounted) return;
      _error = e.toString();
      showError(context, e);
    } finally {
      if (seq == _seq && mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  autofocus: true,
                  controller: _controller,
                  onChanged: _onChanged,
                  onSubmitted: (_) =>
                      _requestSearch(_controller.text.trim()),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _mode == 0 ? '线路名，如: 41路' : '站点名，如: 培元中学',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _controller.clear();
                              _onChanged('');
                            }),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ToggleButtons(
                isSelected: [_mode == 0, _mode == 1],
                onPressed: (m) {
                  if (m == _mode) return;
                  setState(() {
                    _mode = m;
                    _lines = null;
                    _stations = null;
                    _error = null;
                  });
                  final kw = _controller.text.trim();
                  if (kw.isNotEmpty) _requestSearch(kw);
                },
                borderRadius: BorderRadius.circular(10),
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('线路')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('站点')),
                ],
              ),
            ]),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center)));
    }
    if (_lines != null) {
      if (_lines!.isEmpty) {
        return const Center(child: Text('未找到线路（部分城市需要带「路」字，已自动重试）'));
      }
      return _lineList(context);
    }
    if (_stations != null) {
      if (_stations!.isEmpty) {
        return const Center(child: Text('未找到站点'));
      }
      return _stationList(context);
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    return const Center(child: Text('输入关键词，停顿即自动搜索'));
  }

  Widget _lineList(BuildContext context) {
    return ListView.builder(
      itemCount: _lines!.length,
      itemBuilder: (_, i) {
        final l = _lines![i];
        return ListTile(
          leading: const Icon(Icons.directions_bus_outlined),
          title: Text(l.lineName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${l.dirText} · ${l.from} → ${l.to}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            final app = context.read<AppState>();
            app.addHistory(SavedItem(
                type: 'line',
                city: app.city,
                name: l.lineName,
                dir: l.upperOrDown,
                subtitle: '开往${l.to}',
                at: DateTime.now().millisecondsSinceEpoch));
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LineDetailPage(lineName: l.lineName, dir: l.upperOrDown)));
          },
        );
      },
    );
  }

  Widget _stationList(BuildContext context) {
    return ListView.builder(
      itemCount: _stations!.length,
      itemBuilder: (_, i) {
        final s = _stations![i];
        return ListTile(
          leading: const Icon(Icons.place_outlined),
          title: Text(s.stationName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: s.sameNameNum > 0 ? Text('同名站 ${s.sameNameNum} 个') : null,
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            final app = context.read<AppState>();
            app.addHistory(SavedItem(
                type: 'station',
                city: app.city,
                name: s.stationName,
                at: DateTime.now().millisecondsSinceEpoch));
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => StationBoardPage(stationName: s.stationName)));
          },
        );
      },
    );
  }
}
