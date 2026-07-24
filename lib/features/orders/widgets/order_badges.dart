import 'package:flutter/material.dart';

import '../../../core/constants/order_status.dart';

/// 상태별 배지 색. 목업의 색상 팔레트를 따른다(운영자·거래처 화면 공통).
class _BadgeColors {
  const _BadgeColors(this.bg, this.fg);

  final Color bg;
  final Color fg;
}

const Map<OrderStatus, _BadgeColors> _statusColors = <OrderStatus, _BadgeColors>{
  OrderStatus.newOrder: _BadgeColors(Color(0xFFE6F1FB), Color(0xFF0C447C)),
  OrderStatus.processing: _BadgeColors(Color(0xFFFAEEDA), Color(0xFF633806)),
  OrderStatus.shipping: _BadgeColors(Color(0xFFEEEDFE), Color(0xFF3C3489)),
  OrderStatus.done: _BadgeColors(Color(0xFFE1F5EE), Color(0xFF085041)),
  OrderStatus.hold: _BadgeColors(Color(0xFFF1EFE8), Color(0xFF444441)),
};

/// 처리 상태 배지. 운영자용 라벨(신규/처리중/…)과 거래처용 라벨(접수됨/준비중/…)을 구분해 쓴다.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.forPartner = false});

  final OrderStatus status;
  final bool forPartner;

  @override
  Widget build(BuildContext context) {
    final _BadgeColors c = _statusColors[status]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        forPartner ? status.partnerLabel : status.operatorLabel,
        style: TextStyle(fontSize: 11, color: c.fg),
      ),
    );
  }
}

/// 유입 채널 배지(앱/카페24). 두 채널을 같은 목록에서 구분하기 위한 표시.
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.source});

  final OrderSource source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFC9C7BD), width: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(source.label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF8A8880))),
    );
  }
}
