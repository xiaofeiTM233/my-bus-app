import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.location_city_outlined),
                title: const Text('当前城市'),
                subtitle: Text(app.city.isEmpty ? '未选择' : app.city),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final name = await Navigator.of(context).push<String>(
                      MaterialPageRoute(builder: (_) => const CityPickerPage()));
                  if (name != null && name.isNotEmpty) await app.setCity(name);
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
                leading: const Icon(Icons.timer_outlined),
                title: const Text('自动刷新间隔'),
                subtitle: Slider(
                  min: 6,
                  max: 30,
                  divisions: 12,
                  label: '${app.refreshSeconds}秒',
                  value: app.refreshSeconds.toDouble(),
                  onChanged: (v) => app.setRefreshSeconds(v.round()),
                ),
                trailing: Text('${app.refreshSeconds}s'),
              ),
            ]),
          ),
          Card(
            child: Column(children: [
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
            ]),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('数据来源说明',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    '本应用为掌上公交（golbs）的第三方客户端，数据来自其公开查询接口'
                    '（h5.mygolbs.com/ApiData.do），坐标为 GCJ-02（高德系）。\n\n'
                    '接口有频率限制：客户端已强制相邻请求 ≥5 秒 + 随机抖动，'
                    '线路拓扑会本地缓存。仅供个人出行查询，请勿商用或高频抓取。\n\n'
                    '不包含登录、扫码乘车、支付等账号功能。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于 my-bus-app'),
              subtitle: const Text('v0.1.0 · Flutter 第三方掌上公交'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, String msg, VoidCallback onYes) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确定')),
        ],
      ),
    );
    if (yes == true) {
      onYes();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已完成'), duration: Duration(seconds: 1)));
      }
    }
  }
}
