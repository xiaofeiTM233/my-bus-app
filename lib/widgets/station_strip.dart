import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';

/// 横滑站序条（复刻原版站牌样式，对照原版截图）：
/// 顶层站序号 → 绿色轨道（左端"起"徽标、站间白色方向箭头、轨道上的车辆图标）
/// → 站名逐字竖排；当前站为蓝色图钉 + 轨道下方蓝色箭头 + 橙色站名高亮。
class StationStrip extends StatefulWidget {
  final LineDetail detail;
  final RealTime? rt;
  final int currentOrder;
  final ValueChanged<int>? onStationTap;
  final ValueChanged<int>? onStationDoubleTap; // 双击站点 → 站牌页
  const StationStrip({
    super.key,
    required this.detail,
    required this.rt,
    required this.currentOrder,
    this.onStationTap,
    this.onStationDoubleTap,
  });

  @override
  State<StationStrip> createState() => _StationStripState();
}

class _StationStripState extends State<StationStrip> {
  static const _colW = 76.0; // 每站列宽
  static const _trackY = 36.0; // 轨道中线 y
  static const _trackColor = Color(0xFF3CB454); // 轨道绿
  static const _pinColor = Color(0xFF3D7EFF); // 当前站图钉蓝
  static const _hiColor = Color(0xFFF2691B); // 当前站名橙

  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didUpdateWidget(covariant StationStrip old) {
    super.didUpdateWidget(old);
    if (old.currentOrder != widget.currentOrder ||
        old.detail != widget.detail) {
      _scrollToCurrent();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _height {
    final maxLen = widget.detail.stations
        .map((s) => s.showName.length)
        .fold(4, max);
    return 58.0 + maxLen * 17.0 + 8;
  }

  void _scrollToCurrent() {
    if (!_controller.hasClients) return;
    final v = _controller.position.viewportDimension;
    final offset = (widget.currentOrder - 1) * _colW + _colW / 2 - v / 2;
    _controller.animateTo(
      offset.clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stations = widget.detail.stations;
    // 行驶中车辆分组：index=i → 车辆正驶向 1 基站序 i+1，位于站序 i 与 i+1 之间，
    // 即轨道上 x = i * _colW 的边界处（下一站之前，而非之后）
    // 已到站车辆（statusType=0）：index+1 = 所在 1 基站序，画在该站轨道节点上
    final moving = <int, List<BusInfo>>{};
    final arrived = <int, List<BusInfo>>{};
    for (final b in widget.rt?.buses ?? const <BusInfo>[]) {
      if (b.atStation) {
        arrived.putIfAbsent(b.index + 1, () => []).add(b);
      } else {
        moving.putIfAbsent(b.index, () => []).add(b);
      }
    }
    final width = stations.length * _colW + 24;
    final h = _height;
    // 桌面端默认不允许鼠标拖拽滚动，这里放开所有限制设备，
    // 否则站序条在 Windows 上拖不动；另附细滚动条便于拖动。
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: PointerDeviceKind.values.toSet(),
        scrollbars: false,
      ),
      child: Scrollbar(
        controller: _controller,
        thickness: 5,
        thumbVisibility: false,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 绿色轨道（延伸到最右，示意线路延续）
                Positioned(
                  left: 0,
                  right: 0,
                  top: _trackY - 1.5,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: _trackColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // 起点"起"徽标
                Positioned(
                  left: 0,
                  top: _trackY - 9,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: _trackColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '起',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                // 各站：序号 / 节点 / 站名 / 点击区
                for (var i = 0; i < stations.length; i++)
                  _station(i, stations[i], stations.length),
                // 站间：白色方向箭头；有车时用车辆图标替代。
                // 边界 (j+1)*_colW（1 基站序 j+1 与 j+2 之间）上是 index=j+1 的车
                for (var j = 0; j < stations.length - 1; j++)
                  if ((moving[j + 1] ?? const <BusInfo>[]).isEmpty)
                    Positioned(
                      left: (j + 1) * _colW - 6,
                      top: _trackY - 7,
                      child: const Icon(
                        Icons.play_arrow,
                        size: 14,
                        color: Colors.white,
                      ),
                    )
                  else
                    for (var k = 0; k < moving[j + 1]!.length; k++)
                      Positioned(
                        left: (j + 1) * _colW - 11 + k * 22.0,
                        top: _trackY - 11,
                        child: Container(
                          key: ValueKey(
                            'bus-${moving[j + 1]![k].busNumber}-${moving[j + 1]![k].index}',
                          ),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.orange,
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.directions_bus,
                            size: 14,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ),
                // 已到站车辆：画在所在站的轨道节点上（蓝色，区别于行驶中的橙色；
                // 多辆时以节点为中心排开）
                for (final e in arrived.entries)
                  for (var k = 0; k < e.value.length; k++)
                    Positioned(
                      left: (e.key - 1) * _colW +
                          _colW / 2 -
                          11 -
                          (e.value.length - 1) * 11 +
                          k * 22.0,
                      top: _trackY - 11,
                      child: Container(
                        key: ValueKey(
                          'bus-at-${e.value[k].busNumber}-${e.key}',
                        ),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: _pinColor, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.directions_bus,
                          size: 14,
                          color: _pinColor,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _station(int i, LineStation s, int total) {
    final selected = s.order == widget.currentOrder;
    return Positioned(
      left: i * _colW,
      width: _colW,
      top: 0,
      height: _height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 站序号
          Positioned(
            left: 0,
            right: 0,
            top: 4,
            child: Text(
              '${s.order}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
            ),
          ),
          // 轨道节点：当前站为蓝色图钉，其余为绿边白点
          if (selected)
            const Positioned(
              left: _colW / 2 - 11,
              top: _trackY - 17,
              child: Icon(
                Icons.location_on_rounded,
                size: 22,
                color: _pinColor,
              ),
            )
          else
            Positioned(
              left: _colW / 2 - 5,
              top: _trackY - 5,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: _trackColor, width: 2),
                ),
              ),
            ),
          // 当前站：轨道下方的蓝色小箭头
          if (selected)
            const Positioned(
              left: _colW / 2 - 6.5,
              top: _trackY + 4,
              child: Icon(Icons.navigation, size: 13, color: _pinColor),
            ),
          // 站名逐字竖排，当前站橙色加粗
          Positioned(
            left: 4,
            right: 4,
            top: 58,
            child: Text(
              s.showName.split('').join('\n'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? _hiColor : const Color(0xFF333333),
              ),
            ),
          ),
          // 点击区（覆盖整列，置于最上层）：单击选站，双击进站牌页
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onStationTap == null
                  ? null
                  : () => widget.onStationTap!(s.order),
              onDoubleTap: widget.onStationDoubleTap == null
                  ? null
                  : () => widget.onStationDoubleTap!(s.order),
            ),
          ),
        ],
      ),
    );
  }
}
