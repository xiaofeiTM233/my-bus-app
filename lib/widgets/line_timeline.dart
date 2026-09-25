import 'package:flutter/material.dart';

import '../models/models.dart';

/// 纵向站点时间轴：站点行 + 站间车辆徽章。
/// bus.index=i（0 基）→ 行驶中的车画在站点 i 与 i+1 之间；statusType=0（到站）画在站 i 行。
class LineTimeline extends StatelessWidget {
  final LineDetail detail;
  final RealTime? rt;
  final int? selectedOrder;
  final ValueChanged<int> onSelectStation;
  final bool rtLoading;
  const LineTimeline(
      {super.key,
      required this.detail,
      required this.rt,
      required this.selectedOrder,
      required this.onSelectStation,
      required this.rtLoading});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stations = detail.stations;
    final moving = <int, List<BusInfo>>{};
    final arrived = <int, List<BusInfo>>{};
    if (rt != null) {
      for (final b in rt!.buses) {
        if (b.atStation) {
          arrived.putIfAbsent(b.index, () => []).add(b);
        } else {
          moving.putIfAbsent(b.index, () => []).add(b);
        }
      }
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: stations.length * 2 - 1,
      itemBuilder: (context, i) {
        if (i.isOdd) {
          final seg = i ~/ 2; // 站点 seg 与 seg+1 之间
          final buses = moving[seg] ?? const <BusInfo>[];
          return Row(children: [
            const SizedBox(width: 30),
            Container(width: 3, height: buses.isEmpty ? 22 : 30, color: cs.outlineVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [for (final b in buses) _busChip(b)]),
            ),
          ]);
        }
        final idx = i ~/ 2;
        final s = stations[idx];
        final selected = selectedOrder == s.order;
        final atStation = arrived[idx] ?? const <BusInfo>[];
        return InkWell(
          onTap: () => onSelectStation(s.order),
          child: Container(
            color: selected ? cs.primaryContainer.withValues(alpha: 0.4) : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              SizedBox(
                width: 30,
                child: Text('${s.order}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        color: selected ? cs.primary : cs.outline,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? cs.primary : Colors.white,
                  border: Border.all(color: cs.primary, width: 2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.showName,
                    style: TextStyle(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
              ),
              if (s.statusText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(s.statusText!,
                      style: TextStyle(fontSize: 11, color: cs.outline)),
                ),
              if (atStation.isNotEmpty) ...[
                const SizedBox(width: 6),
                for (final b in atStation)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text('到站 ${b.busNumber}',
                        style: const TextStyle(fontSize: 11, color: Colors.white)),
                  ),
              ],
              if (selected && rtLoading)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ]),
          ),
        );
      },
    );
  }

  Widget _busChip(BusInfo b) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        border: Border.all(color: Colors.orange),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('${b.busNumber} 行驶中',
          style: const TextStyle(fontSize: 11, color: Colors.deepOrange)),
    );
  }
}
