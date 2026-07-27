import 'package:flutter/material.dart';

import '../../../core/constants/order_status.dart';

/// 거래처용 발주 진행 단계 바: 접수 → 준비중 → 배송 → 완료.
/// 현재 상태(OrderStatus.step)까지는 완료색, 현재 단계는 강조, 이후는 흐리게 표시한다.
class ProgressSteps extends StatelessWidget {
  const ProgressSteps({super.key, required this.status});

  final OrderStatus status;

  static const List<({String label, IconData icon})> _steps =
      <({String label, IconData icon})>[
    (label: '접수', icon: Icons.check),
    (label: '준비중', icon: Icons.inventory_2_outlined),
    (label: '배송', icon: Icons.local_shipping_outlined),
    (label: '완료', icon: Icons.home_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final int current = status.step; // 1~4
    final List<Widget> row = <Widget>[];
    for (int i = 0; i < _steps.length; i++) {
      if (i > 0) row.add(_connector(i + 1 <= current));
      row.add(_dot(i + 1, current));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: row);
  }

  Widget _connector(bool filled) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 18),
        color: filled ? const Color(0xFF5DCAA5) : const Color(0xFFC9C7BD),
      ),
    );
  }

  Widget _dot(int step, int current) {
    final bool done = step < current || current == 4;
    final bool active = step == current && current != 4;
    Color bg;
    Color fg;
    if (done) {
      bg = const Color(0xFFE1F5EE);
      fg = const Color(0xFF085041);
    } else if (active) {
      bg = const Color(0xFFFAC775);
      fg = const Color(0xFF633806);
    } else {
      bg = Colors.transparent;
      fg = const Color(0xFF8A8880);
    }
    return Column(
      children: <Widget>[
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: (done || active)
                ? null
                : Border.all(color: const Color(0xFFC9C7BD), width: 0.5),
          ),
          child: Icon(_steps[step - 1].icon, size: 15, color: fg),
        ),
        const SizedBox(height: 4),
        Text(
          _steps[step - 1].label,
          style: TextStyle(
            fontSize: 11,
            color: active ? const Color(0xFF1A1A18) : const Color(0xFF5F5E5A),
            fontWeight: active ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
