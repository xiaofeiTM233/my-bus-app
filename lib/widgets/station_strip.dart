import 'package:flutter/material.dart';

import '../models/models.dart';

/// 站牌页横滑站序条：站点列 + 站间车辆图标，自动滚到当前站。
class StationStrip extends StatefulWidget {
  final LineDetail detail;
  final RealTime? rt;
  final int currentOrder;
  const StationStrip(
      {super.key,
      required this.detail,
      required this.rt,
      required this.currentOrder});

  @override
  State<StationStrip> createState() => _StationStripState();
}

class _StationStripState extends State<StationStrip> {
  final _controller = ScrollController();

  @override
  void didUpdateWidget(covariant StationStrip old) {
    super.didUpdateWidget(old);
    if (old.currentOrder != widget.currentOrder) _scrollToCurrent();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  void _scrollToCurrent() {
    if (!_controller.hasClients) return;
    // 站点列宽 76；当前站之前每段可能有车辆列（估宽 56）
    final before = widget.currentOrder - 1;
    var offset = before * 76.0;
    for (final b in widget.rt?.buses ?? const <BusInfo>[]) {
      if (!b.atStation && b.index < before) offset += 56;
    }
    _controller.animateTo(
      offset.clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stations = widget.detail.stations;
    final moving = <int, List<BusInfo>>{};
    for (final b in widget.rt?.buses ?? const <BusInfo>[]) {
      if (!b.atStation) moving.putIfAbsent(b.index, () => []).add(b);
    }
    final children = <Widget>[];
    for (var i = 0; i < stations.length; i++) {
      final s = stations[i];
      final selected = s.order == widget.currentOrder;
      children.add(SizedBox(
        width: 76,
        child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
          Text('${s.order}',
              style: TextStyle(
                  fontSize: 11,
                  color: selected ? cs.primary : cs.outline,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
          Container(
            width: selected ? 14 : 10,
            height: selected ? 14 : 10,
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? cs.primary : Colors.white,
              border: Border.all(color: cs.primary, width: 2),
            ),
          ),
          Text(
            s.showName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.2,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? cs.primary : null,
            ),
          ),
        ]),
      ));
      final buses = moving[i] ?? const <BusInfo>[];
      if (buses.isNotEmpty) {
        children.add(SizedBox(
          width: 56,
          child: Column(children: [
            for (final b in buses)
            Container(
              key: ValueKey('bus-${b.busNumber}-${b.index}'),
              margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.directions_bus,
                    size: 16, color: Colors.deepOrange.shade400),
              ),
          ]),
        ));
      }
    }
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
