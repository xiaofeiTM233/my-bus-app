import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/city_locator.dart';
import '../utils/ui.dart';

/// 选城市：CMD101 全量 565 城 + 定位识别 + 手动输入。
class CityPickerPage extends StatefulWidget {
  const CityPickerPage({super.key});

  @override
  State<CityPickerPage> createState() => _CityPickerPageState();
}

class _CityPickerPageState extends State<CityPickerPage> {
  final _filter = TextEditingController();
  String _keyword = '';
  bool _locating = false;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  /// 定位选城：GPS 定位 → 逆地理识别城市名 → 与服务城市列表匹配。
  Future<void> _locateCity() async {
    if (_locating) return;
    final app = context.read<AppState>();
    setState(() => _locating = true);
    try {
      final loc = await CityLocator().locate();
      await app.setLastLocation(loc.gLat, loc.gLng);
      if (!mounted) return;

      // 1) 与服务城市列表匹配（精确 → 去后缀 → 包含）
      var matched = _matchCity(app.cities, loc.name);
      String note;
      if (matched != null) {
        note = '定位到「${loc.rawName}」\n匹配服务城市：$matched';
      } else if (loc.name.isEmpty) {
        // 2) 兜底：按已缓存的城市中心取最近（80km 内）
        matched = app.nearestCachedCity(loc.gLat, loc.gLng);
        note = matched != null
            ? '无法识别所在城市，按距离匹配最近服务城市：$matched'
            : '定位成功，但无法识别所在城市\n请从列表选择或输入城市名';
      } else {
        // 3) 识别到了但不在服务列表，允许强行使用（同手动输入逻辑）
        matched = loc.rawName;
        note = '当前定位「${loc.rawName}」\n不在服务城市列表中，仍要使用请点「使用」';
      }

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('定位选城'),
          content: Text(note),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            // 识别失败且无兜底城市时没有可用结果，不显示「使用」
            if (matched != null)
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('使用')),
          ],
        ),
      );
      if (ok == true && mounted && matched != null) {
        Navigator.of(context).pop(matched);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// 服务城市匹配：精确命中 → 名称包含定位名（或反之）。
  static String? _matchCity(List<City> cities, String name) {
    if (name.isEmpty) return null;
    for (final c in cities) {
      if (c.name == name) return c.name;
    }
    for (final c in cities) {
      if (c.name.contains(name) || name.contains(c.name)) return c.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cities = app.cities;
    final filtered = _keyword.isEmpty
        ? cities
        : cities.where((c) => c.name.contains(_keyword)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('选择城市')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _locating ? null : _locateCity,
                icon: _locating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location, size: 18),
                label: Text(_locating ? '正在定位识别城市…' : '定位选择当前城市'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _filter,
              onChanged: (v) => setState(() => _keyword = v.trim()),
              decoration: InputDecoration(
                isDense: true,
                hintText: '输入城市名筛选（可直接输入任意城市尝试）',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          if (!app.citiesLoaded)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('正在获取服务城市列表…'),
              ]),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('共 ${cities.length} 个服务城市',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _keyword.isEmpty ? '城市列表为空' : '列表中没有「$_keyword」\n仍要尝试请点击下方按钮',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      leading: filtered[i].name == app.city
                          ? Icon(Icons.check,
                              color: Theme.of(context).colorScheme.primary)
                          : const Icon(Icons.location_city_outlined, size: 18),
                      title: Text(filtered[i].name),
                      onTap: () => Navigator.of(context).pop(filtered[i].name),
                    ),
                  ),
          ),
          if (filtered.isEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(_keyword),
                  child: Text('仍使用「$_keyword」'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
