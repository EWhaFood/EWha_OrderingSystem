import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/order_status.dart';
import '../../core/models/order.dart' as model;
import '../../core/utils/format.dart';
import 'partner_order_detail_screen.dart';
import 'widgets/order_badges.dart';
import 'widgets/progress_steps.dart';

/// 거래처 발주 내역. 자기 partnerId 발주만 실시간 구독한다.
/// 앱 발주와 카페24 몰 주문이 함께 나타나며(출처는 상세에서만 표기), 진행 중/지난 발주로 나눈다.
class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key, required this.uid, required this.partnerId});

  final String uid;
  final String partnerId;

  @override
  Widget build(BuildContext context) {
    final Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('orders')
        .where('partnerId', isEqualTo: partnerId)
        .orderBy('createdAt', descending: true);
    return Scaffold(
      appBar: AppBar(title: const Text('발주 내역')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (BuildContext context,
            AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
          if (snap.hasError) {
            return const Center(child: Text('발주 내역을 불러오지 못했습니다'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<model.Order> orders =
              snap.data!.docs.map(model.Order.fromDoc).toList();
          if (orders.isEmpty) {
            return const Center(
              child: Text('아직 발주 내역이 없습니다',
                  style: TextStyle(color: Color(0xFF8A8880))),
            );
          }
          return _list(context, orders);
        },
      ),
    );
  }

  Widget _list(BuildContext context, List<model.Order> orders) {
    final List<model.Order> active = orders
        .where((model.Order o) =>
            o.status != OrderStatus.done && o.status != OrderStatus.canceled)
        .toList();
    
    final List<model.Order> done = orders
        .where((model.Order o) => o.status == OrderStatus.done)
        .toList();
    final List<model.Order> canceled = orders
        .where((model.Order o) => o.status == OrderStatus.canceled)
        .toList();

    return ListView(
      children: <Widget>[
        for (final model.Order o in active) _ActiveCard(uid: uid, order: o),
        if (done.isNotEmpty) _sectionLabel('지난 발주'),
        for (final model.Order o in done) _PastRow(uid: uid, order: o),
        if (canceled.isNotEmpty) _sectionLabel('취소된 발주'),
        for (final model.Order o in canceled) _PastRow(uid: uid, order: o),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
    );
  }
}

String _summary(model.Order o) {
  if (o.items.isEmpty) return '품목 없음';
  final String first = o.items.first.name;
  return o.items.length > 1 ? '$first 외 ${o.items.length - 1}건' : first;
}

void _openDetail(BuildContext context, String uid, model.Order o) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (BuildContext context) =>
          PartnerOrderDetailScreen(uid: uid, orderId: o.id),
    ),
  );
}

/// 진행 중 발주 카드: 진행 단계 바를 함께 보여준다.
class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.uid, required this.order});

  final String uid;
  final model.Order order;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openDetail(context, uid, order),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F4EF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(order.orderNo,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                const Spacer(),
                StatusBadge(status: order.status, forPartner: true),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Text('${_summary(order)} · ${formatWon(order.totalAmount)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF5F5E5A))),
                if (order.isNextDay) ...<Widget>[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCF0EF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('익일',
                        style: TextStyle(fontSize: 10, color: Color(0xFFA32D2D))),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            ProgressSteps(status: order.status),
          ],
        ),
      ),
    );
  }
}

/// 완료된 지난 발주: 간단한 리스트 행.
class _PastRow extends StatelessWidget {
  const _PastRow({required this.uid, required this.order});

  final String uid;
  final model.Order order;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openDetail(context, uid, order),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE3E1D9), width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(order.orderNo,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                const Spacer(),
                StatusBadge(status: order.status, forPartner: true),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Text('${_summary(order)} · ${formatWon(order.totalAmount)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF5F5E5A))),
                if (order.processDate != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Text('처리: ${DateFormat('MM/dd').format(order.processDate!)}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8A8880),
                          fontWeight: FontWeight.w500)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
