import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../state/app_state.dart';
import 'city_picker_page.dart';

/// 我的：城市管理、刷新间隔、数据维护、说明。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.location_city_outlined),
                  title: const Text('当前城市'),
                  subtitle: Text(app.city.isEmpty ? '未选择' : app.city),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final name = await Navigator.of(context).push<String>(
                      MaterialPageRoute(builder: (_) => const CityPickerPage()),
                    );
                    if (name != null && name.isNotEmpty)
                      await app.setCity(name);
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.map_outlined),
                  title: const Text('地图常驻'),
                  subtitle: const Text('在首页顶部显示地图与附近站点'),
                  value: app.mapAlwaysOn,
                  onChanged: (v) => app.setMapAlwaysOn(v),
                ),
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: const Text('站轴方向'),
                  subtitle: Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('横向'),
                        selected: !app.verticalAxis,
                        onSelected: (_) => app.setVerticalAxis(false),
                      ),
                      ChoiceChip(
                        label: const Text('纵向'),
                        selected: app.verticalAxis,
                        onSelected: (_) => app.setVerticalAxis(true),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('自动刷新间隔'),
                  subtitle: Wrap(
                    spacing: 6,
                    children: [
                      for (final v in const [6, 10, 15, 20, 30])
                        ChoiceChip(
                          label: Text('$v秒'),
                          selected: app.refreshSeconds == v,
                          onSelected: (_) => app.setRefreshSeconds(v),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('清空最近查询'),
                  subtitle: Text('${app.history.length} 条'),
                  onTap: () => _confirm(context, '清空最近查询？', app.clearHistory),
                ),
                ListTile(
                  leading: const Icon(Icons.star_border),
                  title: const Text('清空收藏'),
                  subtitle: Text('${app.favorites.length} 条'),
                  onTap: () => _confirm(context, '清空全部收藏？', app.clearFavorites),
                ),
              ],
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('掌上公交'),
                  subtitle: Text(
                    'v$appVersion（Flutter）'
                    '${commitShort.isEmpty ? '' : ' · $commitShort'}',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('GitHub 仓库'),
                  subtitle: const Text(repoUrl),
                  trailing: const Icon(Icons.copy, size: 18),
                  onTap: () {
                    Clipboard.setData(const ClipboardData(text: repoUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('仓库地址已复制'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    String msg,
    VoidCallback onYes,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (yes == true) {
      onYes();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已完成'), duration: Duration(seconds: 1)),
        );
      }
    }
  }
}
