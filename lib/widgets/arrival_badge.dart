import 'package:flutter/material.dart';

import '../models/models.dart';

/// 到站信息徽章：即将到站(绿/加粗) / N站·N分钟 · 距离 / 停运灰字。
class ArrivalBadge extends StatelessWidget {
  final Arrival arrival;
  const ArrivalBadge({super.key, required this.arrival});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (color, bold) = switch (arrival.state) {
      ArrivalState.arriving => (cs.primary, true),
      ArrivalState.approaching => (cs.onSurface, false),
      ArrivalState.noService => (cs.outline, false),
      ArrivalState.unknown => (cs.outline, false),
    };
    return Text(
      arrival.summary,
      style: TextStyle(color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
    );
  }
}
