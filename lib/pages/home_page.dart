import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/ui.dart';
import '../widgets/city_bar.dart';
import '../widgets/map_banner.dart';
import '../widgets/station_tabs.dart';
import 'city_picker_page.dart';
import 'map_page.dart';
import 'search_page.dart';
import 'transfer_page.dart';

/// 首页：城市栏 + 宫格入口 + 站点面板（附近/最近/收藏，M1-B 接入）。
class HomePage extends StatefulWidget {
  final VoidCallback onGoMap;
  const HomePage({super.key, required this.onGoMap});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _pickerShown = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_init);
  }

  Future<void> _init() async {
    final app = context.read<AppState>();
    try {
      await app.ensureCities();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted && !app.ready && !_pickerShown) {
      _pickerShown = true;
      await _pickCity();
    }
  }

  Future<void> _pickCity() async {
    final app = context.read<AppState>();
    final name = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CityPickerPage()),
    );
    if (name != null && name.isNotEmpty) await app.setCity(name);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (app.mapAlwaysOn)
              MapBanner(height: 170),
            CityBar(
              city: app.city,
              onPickCity: _pickCity,
              onSearch: _openSearch,
              onMap: widget.onGoMap,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  _GridCard(icon: Icons.alt_route, label: '换乘规划', onTap: _openTransfer),
                  const SizedBox(width: 10),
                  _GridCard(icon: Icons.map_outlined, label: '地图查车', onTap: _openMap),
                ],
              ),
            ),
            const Divider(height: 1),
            const Expanded(child: StationTabs()),
          ],
        ),
      ),
    );
  }

  Future<void> _openSearch() async {
    final app = context.read<AppState>();
    if (!app.ready) {
      showError(context, '请先选择城市');
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SearchPage()));
  }

  void _openTransfer() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TransferPage()));
  }

  void _openMap() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const MapPage()));
  }
}

class _GridCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _GridCard({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Icon(icon, color: cs.primary),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}
