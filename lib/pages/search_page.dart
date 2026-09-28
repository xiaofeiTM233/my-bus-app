import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/mybus_client.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/ui.dart';
import 'line_detail_page.dart';
import 'station_board_page.dart';

/// 搜索页：一次输入同时搜线路（CMD114）与站点（CMD110），结果分组展示。
/// 输入即搜（latest-wins：执行中时新关键词覆盖排队旧词，
/// 响应按序号丢弃过期结果；两个请求共用取消令牌）。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  int _seq = 0; // 递增序号，响应返回时序号不一致则丢弃
  bool _loading = false;
  bool _running = false; // 已有一个搜索在执行/排队
  String? _queuedKw; // 排队中的最新关键词（永远只保留一个）
  CancelToken? _searchToken; // 在途搜索的取消令牌（线路/站点共用）
  String? _error;
  List<LineSummary>? _lines;
  List<StationHit>? _stations;

  @override
  void dispose() {
    _searchToken?.cancel();
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

  /// 单个搜索的安全封装：出错转 null，非取消错误提示一次。
  Future<T?> _safe<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on MyBusException catch (e) {
      if (!e.cancelled && mounted) showError(context, e);
      return null;
    }
  }

  Future<void> _search(String kw, int seq) async {
    final app = context.read<AppState>();
    setState(() => _loading = true);
    _searchToken?.cancel(); // 新搜索直接取消在途旧请求
    final token = CancelToken();
    _searchToken = token;
    final results = await Future.wait([
      _safe(() => app.client.searchLine(app.city, kw, cancelToken: token)),
      _safe(() => app.client.searchStation(app.city, kw, cancelToken: token)),
    ]);
    if (seq != _seq || !mounted) return;
    setState(() {
      _lines = results[0] as List<LineSummary>?;
      _stations = results[1] as List<StationHit>?;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              controller: _controller,
              onChanged: _onChanged,
              onSubmitted: (_) => _requestSearch(_controller.text.trim()),
              decoration: InputDecoration(
                isDense: true,
                hintText: '线路或站点名，如: 41路 / 培元中学',
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
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary)),
      );

  Widget _buildBody(BuildContext context) {
    if (_error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center)));
    }
    if (_lines != null || _stations != null) {
      final hasLines = _lines != null && _lines!.isNotEmpty;
      final hasStations = _stations != null && _stations!.isNotEmpty;
      if (!hasLines && !hasStations) {
        return const Center(
            child: Text('未找到相关线路或站点\n（部分城市线路需带「路」字，已自动重试）',
                textAlign: TextAlign.center));
      }
      return ListView(
        children: [
          if (hasLines) ...[
            _sectionHeader('线路'),
            for (final l in _lines!) _lineTile(context, l),
          ],
          if (hasStations) ...[
            _sectionHeader('站点'),
            for (final s in _stations!) _stationTile(context, s),
          ],
          const SizedBox(height: 12),
        ],
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    return const Center(child: Text('输入关键词，同时搜索线路与站点'));
  }

  Widget _lineTile(BuildContext context, LineSummary l) {
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
  }

  Widget _stationTile(BuildContext context, StationHit s) {
    return ListTile(
      leading: const Icon(Icons.place_outlined),
      title: Text(stationNameHorizontal(s.stationName),
          style: const TextStyle(fontWeight: FontWeight.w600)),
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
  }
}
