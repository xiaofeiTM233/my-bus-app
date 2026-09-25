/// 全局状态：城市、收藏、最近、设置（shared_preferences 持久化）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/mybus_client.dart';
import '../models/models.dart';

/// 收藏与最近共用的条目。type: 'line'（name=线路名, dir=方向, order=收藏时站序）
/// 或 'station'（name=站名）。
class SavedItem {
  final String type;
  final String city;
  final String name;
  final String? dir;
  final int? order;
  final String? subtitle;
  final int at;

  SavedItem({
    required this.type,
    required this.city,
    required this.name,
    this.dir,
    this.order,
    this.subtitle,
    required this.at,
  });

  String get key => '$type|$city|$name|${dir ?? ''}';

  Map<String, dynamic> toJson() => {
        'type': type,
        'city': city,
        'name': name,
        'dir': dir,
        'order': order,
        'subtitle': subtitle,
        'at': at,
      };

  factory SavedItem.fromJson(dynamic j) => SavedItem(
        type: _s(j['type']),
        city: _s(j['city']),
        name: _s(j['name']),
        dir: j['dir']?.toString(),
        order: j['order'] == null ? null : int.tryParse(j['order'].toString()),
        subtitle: j['subtitle']?.toString(),
        at: j['at'] == null ? 0 : int.tryParse(j['at'].toString()) ?? 0,
      );

  static String _s(dynamic v) => v == null ? '' : v.toString();
}

class AppState extends ChangeNotifier {
  AppState({required this.client});

  final MyBusClient client;

  String city = '';
  List<City> cities = [];
  bool citiesLoaded = false;
  int refreshSeconds = 10; // 自动刷新间隔（≥6）
  List<SavedItem> favorites = [];
  List<SavedItem> history = [];

  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    city = p.getString('city') ?? '';
    refreshSeconds = p.getInt('refreshSeconds') ?? 10;
    favorites = _decodeList(p.getString('favorites'));
    history = _decodeList(p.getString('history'));
    notifyListeners();
  }

  static List<SavedItem> _decodeList(String? raw) {
    // 注意必须返回可增长列表：const [] 会让 addHistory/removeWhere 抛 UnsupportedError
    if (raw == null || raw.isEmpty) return <SavedItem>[];
    try {
      return [
        for (final e in (jsonDecode(raw) as List)) SavedItem.fromJson(e)
      ];
    } catch (_) {
      return <SavedItem>[];
    }
  }

  void _save(String key, List<SavedItem> items) {
    _prefs?.setString(
        key, jsonEncode([for (final i in items) i.toJson()]));
  }

  bool get ready => city.isNotEmpty;

  /// CMD101 城市列表（只拉一次）。
  Future<void> ensureCities() async {
    if (citiesLoaded) return;
    cities = await client.cityList();
    citiesLoaded = true;
    notifyListeners();
  }

  Future<void> setCity(String name) async {
    city = name;
    await _prefs?.setString('city', name);
    notifyListeners();
  }

  Future<void> setRefreshSeconds(int v) async {
    refreshSeconds = v.clamp(6, 120);
    await _prefs?.setInt('refreshSeconds', refreshSeconds);
    notifyListeners();
  }

  /// 查询/打开详情时记录最近（去重、上限 20）。
  void addHistory(SavedItem item) {
    history.removeWhere((e) => e.key == item.key);
    history.insert(0, item);
    if (history.length > 20) history.removeRange(20, history.length);
    _save('history', history);
    notifyListeners();
  }

  void removeHistory(SavedItem item) {
    history.removeWhere((e) => e.key == item.key);
    _save('history', history);
    notifyListeners();
  }

  void clearHistory() {
    history = [];
    _save('history', history);
    notifyListeners();
  }

  bool isFavorite(SavedItem item) =>
      favorites.any((e) => e.key == item.key);

  void toggleFavorite(SavedItem item) {
    if (isFavorite(item)) {
      favorites.removeWhere((e) => e.key == item.key);
    } else {
      favorites.insert(0, item);
    }
    _save('favorites', favorites);
    notifyListeners();
  }

  void removeFavorite(SavedItem item) {
    favorites.removeWhere((e) => e.key == item.key);
    _save('favorites', favorites);
    notifyListeners();
  }

  void clearFavorites() {
    favorites = [];
    _save('favorites', favorites);
    notifyListeners();
  }
}
