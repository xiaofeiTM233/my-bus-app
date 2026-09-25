import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/ui.dart';
import 'line_detail_page.dart';
import 'station_board_page.dart';

/// 搜索页：线路 / 站点 双模式。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  int _mode = 0; // 0=线路 1=站点
  bool _loading = false;
  String? _error;
  List<LineSummary>? _lines;
  List<StationHit>? _stations;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final kw = _controller.text.trim();
    final app = context.read<AppState>();
    if (kw.isEmpty || app.city.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_mode == 0) {
        _stations = null;
        _lines = await app.client.searchLine(app.city, kw);
      } else {
        _lines = null;
        _stations = await app.client.searchStation(app.city, kw);
      }
    } catch (e) {
      _error = e.toString();
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
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
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _mode == 0 ? '线路名，如: 41路' : '站点名，如: 培元中学',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ToggleButtons(
                isSelected: [_mode == 0, _mode == 1],
                onPressed: (i) => setState(() {
                  _mode = i;
                  _lines = null;
                  _stations = null;
                  _error = null;
                }),
                borderRadius: BorderRadius.circular(10),
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('线路')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('站点')),
                ],
              ),
            ]),
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
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
    if (_stations != null) {
      if (_stations!.isEmpty) {
        return const Center(child: Text('未找到站点'));
      }
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
    return const Center(child: Text('输入关键词开始查询'));
  }
}
