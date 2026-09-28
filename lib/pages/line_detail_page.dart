import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/geo.dart';
import '../utils/ui.dart';
import '../widgets/line_map.dart';
import '../widgets/line_timeline.dart';
import '../widgets/station_strip.dart';
import 'station_board_page.dart';

/// 路线页（参考原版线路详情）：
/// 头部（起终点/换向/首末班/起点预计发车/等车站）→ 双班车预测横幅 →
/// 站轴（站序条/时间轴/地图）→ 底部「多线路对比」（等车站/下车站选择）。
/// 单击「等车站」站名弹出站台菜单（站点信息/同站线路），导航入口置灰。
class LineDetailPage extends StatefulWidget {
  final String lineName;
  final String dir;
  final int? initialOrder;
  const LineDetailPage({
    super.key,
    required this.lineName,
    required this.dir,
    this.initialOrder,
  });

  @override
  State<LineDetailPage> createState() => _LineDetailPageState();
}

class _LineDetailPageState extends State<LineDetailPage> {
  late String _dir;
  LineDetail? _detail;
  bool _loading = true;
  Object? _error;
  int? _selectedOrder;
  RealTime? _rt;
  bool _rtLoading = false;
  bool _mapView = false;
  bool _horizontalAxis = false; // 站点轴横向（默认纵向时间轴）
  Timer? _timer;

  /// 切换方向前选中的站名：对向线路里按站名重新定位
  /// （两个方向站序体系完全不同，按站序找会定位到另一个站）
  String? _pendingStationName;

  // 等车站站台（CMD115/209）：所选站点的站台坐标可经「等车站」下拉切换
  List<StationLine>? _stationLines;
  List<NearbyStation>? _platforms;
  double? _stationLat;
  double? _stationLng;

  /// 下车站（站序）；null = 未选择
  int? _alightOrder;

  @override
  void initState() {
    super.initState();
    _dir = widget.dir;
    // 默认站轴方向跟随设置：横向→站序条，纵向→时间轴
    _horizontalAxis = !context.read<AppState>().verticalAxis;
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  AppState get _app => context.read<AppState>();

  LineStation? get _selectedStation => _selectedOrder == null
      ? null
      : _detail?.stations.where((s) => s.order == _selectedOrder).firstOrNull;

  Future<void> _load() async {
    final app = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await app.client.lineStations(app.city, widget.lineName, _dir);
      if (!mounted) return;
      _detail = d;
      _stationLines = null;
      _platforms = null;
      _alightOrder = null;
      app.addHistory(
        SavedItem(
          type: 'line',
          city: app.city,
          name: widget.lineName,
          dir: _dir,
          subtitle: d.stations.isEmpty ? null : '开往${d.stations.last.showName}',
          at: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (_selectedOrder == null) {
        // 优先按站名定位（切换方向后同一物理站的对向站序）；
        // 其次用入口指定的初始站序（仅首次，且校验不越界）
        final byName = _pendingStationName == null
            ? null
            : d.stations
                .where((s) =>
                    s.name == _pendingStationName ||
                    (s.name.isEmpty && s.showName == _pendingStationName))
                .firstOrNull;
        if (byName != null) {
          _selectStation(byName.order);
        } else if (widget.initialOrder != null &&
            widget.initialOrder! >= 1 &&
            widget.initialOrder! <= d.stations.length) {
          _selectStation(widget.initialOrder!);
        }
      }
      _pendingStationName = null;
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      _error = e;
      showError(context, e);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 启动实时轮询。未选站时以首站序查询：CMD104 的 list 是全线车辆
  /// （每辆车带 index/绝对坐标），足够画出全线车辆位置与站间徽章；
  /// 选中站后相对该站查询，额外提供精确到站预测。
  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: _app.refreshSeconds),
      (_) {
        _fetchRt(silent: true);
        _fetchStationLines(silent: true);
      },
    );
    _fetchRt(silent: true);
  }

  void _selectStation(int order) {
    setState(() => _selectedOrder = order);
    _alightOrder = null;
    _startPolling();
    _fetchStationLines();
  }

  Future<void> _fetchRt({bool silent = false}) async {
    final app = context.read<AppState>();
    if (!app.ready) return;
    final order = _selectedOrder ?? 1;
    if (!silent) setState(() => _rtLoading = true);
    try {
      final rt = await app.client.realtime(
        app.city,
        widget.lineName,
        _dir,
        order,
      );
      if (!mounted) return;
      setState(() => _rt = rt);
    } catch (e) {
      if (!silent && mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _rtLoading = false);
    }
  }

  /// 拉取等车站的多线路对比（CMD115，ALL=1）与同名站台（CMD209）。
  Future<void> _fetchStationLines({bool silent = false}) async {
    final st = _selectedStation;
    if (st == null || st.name.isEmpty) return;
    final app = context.read<AppState>();
    if (!silent) setState(() {});
    try {
      var lines = await app.client.stationLines(
        app.city,
        st.name,
        lat: _stationLat?.toStringAsFixed(6),
        lng: _stationLng?.toStringAsFixed(6),
        all: true,
      );
      // 坐标偏差导致查空时去坐标重试
      if (lines.isEmpty && (_stationLat != null || _stationLng != null)) {
        lines = await app.client.stationLines(app.city, st.name, all: true);
      }
      _stationLines = lines;
      // 同名站台（等车站选择器候选），失败静默
      if (_platforms == null) {
        try {
          _platforms = await app.client.stationPlatforms(
            app.city,
            st.name,
            myLat: _stationLat?.toStringAsFixed(6),
            myLng: _stationLng?.toStringAsFixed(6),
            lat: _stationLat?.toStringAsFixed(6),
            lng: _stationLng?.toStringAsFixed(6),
          );
        } catch (_) {
          _platforms = null;
        }
      }
    } catch (_) {
      _stationLines = null;
    }
    if (mounted) setState(() {});
  }

  void _switchDir(String d) {
    if (d == _dir) return;
    _timer?.cancel();
    // 记住当前选中的站名：新方向加载后按站名重新定位对向站台
    _pendingStationName = _selectedOrder == null
        ? null
        : _detail?.stations
            .where((s) => s.order == _selectedOrder)
            .firstOrNull
            ?.name;
    setState(() {
      _dir = d;
      _selectedOrder = null;
      _rt = null;
      _detail = null;
      _stationLines = null;
      _platforms = null;
      _alightOrder = null;
    });
    _load();
  }

  /// 「等车站」切换到指定站台（CMD209 候选）：更新坐标并重查多线路对比。
  Future<void> _switchPlatform(NearbyStation p) async {
    setState(() {
      _stationLat = p.lat;
      _stationLng = p.lon;
      _stationLines = null;
    });
    await _fetchStationLines();
  }

  /// 单击「等车站」站名 → 站台菜单（取代原双击跳转）。
  void _showStationMenu() {
    final st = _selectedStation;
    if (st == null || !mounted) return;
    final orange = const Color(0xFFF2691B);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                stationNameHorizontal(st.showName),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: Icon(Icons.directions_bus_outlined, color: orange),
              title: const Text('站点信息'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StationBoardPage(
                    stationName: st.name,
                    lat: st.lat == 0 ? null : st.lat.toStringAsFixed(6),
                    lng: st.lon == 0 ? null : st.lon.toStringAsFixed(6),
                  ),
                ));
              },
            ),
            ListTile(
              leading: Icon(Icons.alt_route, color: orange),
              title: const Text('同站线路'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StationBoardPage(
                    stationName: st.name,
                    lat: st.lat == 0 ? null : st.lat.toStringAsFixed(6),
                    lng: st.lon == 0 ? null : st.lon.toStringAsFixed(6),
                  ),
                ));
              },
            ),
            ListTile(
              leading: Icon(Icons.near_me_outlined, color: Colors.grey),
              title: const Text('去往这里',
                  style: TextStyle(color: Colors.grey)),
              trailing:
                  const Text('开发中', style: TextStyle(color: Colors.grey)),
              onTap: null,
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  void _openLine(StationLine l) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LineDetailPage(
          lineName: l.lineName,
          dir: l.upperOrDown,
          initialOrder: l.stationOrder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final fav = SavedItem(
      type: 'line',
      city: app.city,
      name: widget.lineName,
      dir: _dir,
      at: 0,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lineName),
        actions: [
          IconButton(
            onPressed: _selectedOrder == null ? null : _fetchRt,
            tooltip: '手动刷新',
            icon: _rtLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(context),
      bottomNavigationBar: _bottomBar(context, app.isFavorite(fav)),
    );
  }

  /// 底部操作栏（参考原版：收藏 / 提醒 / 地图 / 站轴；反馈与更多不实现）。
  Widget _bottomBar(BuildContext context, bool fav) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE5E5E5))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _BarItem(
              fav ? Icons.star : Icons.star_border,
              '收藏',
              onTap: () => context.read<AppState>().toggleFavorite(SavedItem(
                    type: 'line',
                    city: context.read<AppState>().city,
                    name: widget.lineName,
                    dir: _dir,
                    subtitle: _detail == null || _detail!.stations.isEmpty
                        ? null
                        : '开往${_detail!.stations.last.showName}',
                    at: DateTime.now().millisecondsSinceEpoch,
                  )),
              active: fav,
            ),
            const _BarItem(Icons.notifications_none, '提醒'),
            _BarItem(
              _mapView ? Icons.view_list : Icons.map_outlined,
              '地图',
              onTap: () => setState(() => _mapView = !_mapView),
              active: _mapView,
            ),
            _BarItem(
              _horizontalAxis ? Icons.swap_vert : Icons.swap_horiz,
              '站轴',
              onTap: _mapView
                  ? null
                  : () => setState(() => _horizontalAxis = !_horizontalAxis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return _loadingView();
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$_error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final d = _detail!;
    final hasStation = _selectedOrder != null;
    return Column(
      children: [
        _headerCard(context, d),
        if (hasStation) _predictionBanner(context),
        if (_mapView)
          Expanded(
            child: LineMapWidget(
              detail: d,
              rt: _rt,
              selectedOrder: _selectedOrder,
            ),
          )
        else if (_horizontalAxis) ...[
          SizedBox(
            height: 250,
            child: Card(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: StationStrip(
                detail: d,
                rt: _rt,
                currentOrder: _selectedOrder ?? 1,
                onStationTap: _selectStation,
              ),
            ),
          ),
          if (hasStation)
            _stationBoardSection(expand: true)
          else
            const Spacer(),
        ] else ...[
          Expanded(
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: LineTimeline(
                detail: d,
                rt: _rt,
                selectedOrder: _selectedOrder,
                onSelectStation: _selectStation,
                rtLoading: _rtLoading,
              ),
            ),
          ),
          if (hasStation) _stationBoardSection(expand: false),
        ],
      ],
    );
  }

  Widget _loadingView() => const Center(child: CircularProgressIndicator());

  /// 头部卡片：起终点 + 换向 / 首末班 / 起点预计发车 + 等车站（可点弹菜单）。
  Widget _headerCard(BuildContext context, LineDetail d) {
    const orange = Color(0xFFF2691B);
    final fl = d.firstLast.isEmpty ? null : d.firstLast.first;
    final plan = _rt?.planTime ?? '';
    final st = _selectedStation;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    d.stations.length < 2
                        ? '—'
                        : '${d.stations.first.showName} → ${d.stations.last.showName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('换向',
                      style: TextStyle(
                          color: orange, fontWeight: FontWeight.w600)),
                  side: const BorderSide(color: orange),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _switchDir(_dir == '1' ? '2' : '1'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '首班 ${fl?.first ?? '--'} · 末班 ${fl?.last ?? '--'}'
              '${d.comments.isEmpty ? '' : ' · ${d.comments}'}'
              ' · 共${d.stations.length}站',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '起点预计发车：'
                  '${plan.isEmpty ? '--' : plan}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                GestureDetector(
                  onTap: st == null ? null : _showStationMenu,
                  child: Text(
                    st == null
                        ? '等车站：选择站点'
                        : '等车站：${stationNameHorizontal(st.showName)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: st == null
                          ? Theme.of(context).textTheme.bodySmall?.color
                          : orange,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 双班车预测横幅（参考原版）：左=最近车辆，右=下一班。
  Widget _predictionBanner(BuildContext context) {
    const orange = Color(0xFFF2691B);
    final rt = _rt;
    final List<(String, String)> cells;
    if (rt == null) {
      cells = [(_rtLoading ? '加载中…' : '—', '')];
    } else if (rt.stopped) {
      cells = [('该线路已停运', '')];
    } else if (!rt.hasRealtime) {
      cells = [('暂无实时数据', rt.planTime.isEmpty ? '' : '计划班次 ${rt.planTime}')];
    } else if (rt.predictions.isEmpty) {
      cells = [('暂无车辆接近', '')];
    } else {
      cells = [
        for (final p in rt.predictions.take(2))
          (p.tips.isEmpty ? '即将到站' : p.tips,
              [p.timeTips, p.distTips].where((s) => s.isNotEmpty).join(' / ')),
      ];
    }
    return Container(
      width: double.infinity, // 单条内容时也保持满宽（避免被外层 Column 收缩居中）
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF2E3), Color(0xFFFFE2C6)],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      // 只有一条信息（一辆车/等待发车/停运等）时整体居中，不显示右侧空栏
      child: cells.length == 1
          ? Column(
              children: [
                Text(
                  cells[0].$1,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: orange,
                  ),
                ),
                if (cells[0].$2.isNotEmpty)
                  Text(
                    cells[0].$2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: orange),
                  ),
              ],
            )
          : Row(
              children: [
                for (var i = 0; i < 2; i++) ...[
                  if (i == 1)
                    Container(
                        width: 1, height: 36, color: const Color(0xFFF2C9A0)),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          cells[i].$1,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: orange,
                          ),
                        ),
                        if (cells[i].$2.isNotEmpty)
                          Text(
                            cells[i].$2,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, color: orange),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  /// 底部「多线路对比」（参考原版）：等车站/下车站选择器 + 经过本站的线路。
  Widget _stationBoardSection({required bool expand}) {
    const orange = Color(0xFFF2691B);
    final st = _selectedStation;
    if (st == null) return const SizedBox.shrink();
    final alights = _detail?.stations
            .where((s) => _selectedOrder != null && s.order > _selectedOrder!)
            .toList() ??
        <LineStation>[];

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('多线路对比',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              const Text('等车站',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(width: 6),
              Expanded(
                child: _platformSelector(st),
              ),
              const SizedBox(width: 12),
              const Text('下车站',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButton<int>(
                  value: _alightOrder,
                  isExpanded: true,
                  isDense: true,
                  hint: const Text('选择下车站',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13)),
                  items: [
                    for (final s in alights)
                      DropdownMenuItem(
                        value: s.order,
                        child: Text(
                          stationNameHorizontal(s.showName),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _alightOrder = v),
                  underline: const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
        if (_alightOrder != null && _selectedOrder != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              '从等车站到「${stationNameHorizontal(alights.where((s) => s.order == _alightOrder).firstOrNull?.showName ?? '')}」'
              '还有 ${_alightOrder! - _selectedOrder!} 站',
              style: const TextStyle(fontSize: 12, color: orange),
            ),
          ),
        ],
        const Divider(height: 12),
        Expanded(
          child: _stationLines == null
              ? const Center(
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : _stationLines!.isEmpty
                  ? const Center(
                      child: Text('该站台暂无线路数据',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: _stationLines!.length,
                      separatorBuilder: (_, _) => const Divider(
                          height: 1, thickness: 0.5, indent: 16, endIndent: 16),
                      itemBuilder: (_, i) {
                        final l = _stationLines![i];
                        final arrival = arrivalOf(l);
                        final statusColor = switch (arrival.state) {
                          ArrivalState.arriving => const Color(0xFF3CB454),
                          ArrivalState.noService => orange,
                          _ => orange,
                        };
                        final secondary = [
                          if (l.nearTime.isNotEmpty) l.nearTime,
                          if (l.nearDis.isNotEmpty) l.nearDis,
                        ].join(' / ');
                        return ListTile(
                          dense: true,
                          onTap: () => _openLine(l),
                          title: Text(
                            l.lineName,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '方向 ${l.upperOrDown == '1' ? '上行' : '下行'} · 本站第${l.stationOrder}站',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          trailing: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                arrival.summary,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                ),
                              ),
                              if (secondary.isNotEmpty)
                                Text(secondary,
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
    return expand
        ? Expanded(child: content)
        : SizedBox(height: 240, child: content);
  }

  /// 等车站选择器：同名站台（CMD209）下拉，切换后重查该站台线路。
  Widget _platformSelector(LineStation st) {
    final platforms = _platforms;
    if (platforms == null || platforms.length < 2) {
      return Text(
        stationNameHorizontal(st.showName),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      );
    }
    // 当前站台 = 距现用坐标最近的候选
    var cur = 0;
    final lat = _stationLat;
    final lng = _stationLng;
    for (var i = 0; i < platforms.length; i++) {
      if (lat != null &&
          lng != null &&
          distMeters(lat, lng, platforms[i].lat, platforms[i].lon) < 50) {
        cur = i;
        break;
      }
    }
    return DropdownButton<int>(
      value: cur,
      isExpanded: true,
      isDense: true,
      items: [
        for (var i = 0; i < platforms.length; i++)
          DropdownMenuItem(
            value: i,
            child: Text(
              '${stationNameHorizontal(platforms[i].name)}（${platforms[i].dis}米）',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
      onChanged: (v) {
        if (v == null || v == cur) return;
        _switchPlatform(platforms[v]);
      },
      underline: const SizedBox.shrink(),
    );
  }
}

/// 底部操作栏按钮。
class _BarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  const _BarItem(this.icon, this.label, {this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color =
        onTap == null ? cs.outline : (active ? cs.primary : cs.onSurfaceVariant);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}
