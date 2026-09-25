import 'package:flutter/material.dart';

/// 首页顶栏：城市选择 + 搜索框 + 地图入口。
class CityBar extends StatelessWidget {
  final String city;
  final VoidCallback onPickCity;
  final VoidCallback onSearch;
  final VoidCallback onMap;
  const CityBar(
      {super.key,
      required this.city,
      required this.onPickCity,
      required this.onSearch,
      required this.onMap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPickCity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(children: [
                Text(city.isEmpty ? '选择城市' : city,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Icon(Icons.arrow_drop_down),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              readOnly: true,
              onTap: onSearch,
              decoration: InputDecoration(
                isDense: true,
                hintText: '输入线路或站点查询',
                prefixIcon: const Icon(Icons.search, size: 22),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
              ),
            ),
          ),
          IconButton(onPressed: onMap, icon: const Icon(Icons.map_outlined), tooltip: '地图'),
        ],
      ),
    );
  }
}
