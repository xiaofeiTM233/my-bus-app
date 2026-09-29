import 'package:flutter/material.dart';

import '../models/models.dart';

/// 站点线路对比列表（站牌页 / 路线页「多线路对比」共用样式）。
///
/// 每行：车号（粗体）+「当前」徽章（可选）｜右侧实时状态 + 时间/距离；
/// 副标题：方向 · 本站站序。
class StationLinesList extends StatelessWidget {
  final List<StationLine> lines;

  /// 当前线路标识（`lineName|upperOrDown`），命中行显示「当前」徽章
  final String? currentKey;

  final void Function(StationLine line)? onTap;

  const StationLinesList({
    super.key,
    required this.lines,
    this.currentKey,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFF2691B);
    const green = Color(0xFF3CB454);
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: lines.length,
      separatorBuilder: (_, _) => const Divider(
          height: 1, thickness: 0.5, indent: 16, endIndent: 16),
      itemBuilder: (_, i) {
        final l = lines[i];
        final arrival = arrivalOf(l);
        final statusColor = switch (arrival.state) {
          ArrivalState.arriving => green,
          ArrivalState.noService => orange,
          _ => orange,
        };
        final secondary = [
          if (l.nearTime.isNotEmpty) l.nearTime,
          if (l.nearDis.isNotEmpty) l.nearDis,
        ].join(' / ');
        final isCurrent =
            currentKey != null && currentKey == '${l.lineName}|${l.upperOrDown}';
        return ListTile(
          dense: true,
          onTap: onTap == null ? null : () => onTap!(l),
          title: Row(
            children: [
              Text(
                l.lineName,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    border: Border.all(color: orange),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('当前',
                      style: TextStyle(fontSize: 11, color: orange)),
                ),
              ],
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    arrival.summary,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: statusColor),
                  ),
                  if (secondary.isNotEmpty)
                    Text(secondary,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ],
          ),
          subtitle: Text(
            '方向 ${l.upperOrDown == '1' ? '上行' : '下行'} · 本站第${l.stationOrder}站',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        );
      },
    );
  }
}
