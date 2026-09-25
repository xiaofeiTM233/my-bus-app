import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// 选城市：CMD101 全量 565 城 + 手动输入。
class CityPickerPage extends StatefulWidget {
  const CityPickerPage({super.key});

  @override
  State<CityPickerPage> createState() => _CityPickerPageState();
}

class _CityPickerPageState extends State<CityPickerPage> {
  final _filter = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
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
