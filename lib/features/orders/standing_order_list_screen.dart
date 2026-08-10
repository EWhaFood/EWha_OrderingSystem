import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/partner.dart';
import '../../core/models/standing_order.dart';
import '../../core/services/standing_order_service.dart';
import '../../core/utils/format.dart';
import 'standing_order_form_screen.dart';

class StandingOrderListScreen extends StatelessWidget {
  const StandingOrderListScreen({
    super.key,
    required this.partner,
  });

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('정기발주'),
      ),
      body: StreamBuilder<List<StandingOrder>>(
        stream: StandingOrderService.watch(partner.id),
        builder: (context, snap) {
          if (snap.hasError) {
            debugPrint('StandingOrder Error: ${snap.error}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  '데이터를 불러오는 중 오류가 발생했습니다.\nFirestore 인덱스 설정을 확인해주세요.\n\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final orders = snap.data!;
          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_today_outlined, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text(
                    '등록된 정기발주 내역이 없습니다.',
                    style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '하단의 + 버튼을 눌러 새로운 정기발주를 등록해보세요.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _StandingOrderCard(
              order: orders[index],
              partner: partner,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _openForm(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StandingOrderFormScreen(partner: partner),
      ),
    );
  }
}

class _StandingOrderCard extends StatelessWidget {
  const _StandingOrderCard({required this.order, required this.partner});

  final StandingOrder order;
  final Partner partner;

  @override
  Widget build(BuildContext context) {
    final isPaused = order.status == StandingOrderStatus.paused;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.favoriteName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                _statusBadge(order.status),
              ],
            ),
            const SizedBox(height: 8),
            Text('주기: ${order.cycle.label}'),
            Text('희망 시간: ${order.preferredTime.format(context)}'),
            Text('다음 발주 예정: ${order.nextOrderDate != null ? DateFormat('yyyy/MM/dd').format(order.nextOrderDate!) : "미정"}'),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _togglePause(context),
                  child: Text(isPaused ? '재개' : '일시중지'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _cancel(context),
                  child: const Text('해지', style: TextStyle(color: Colors.red)),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () => _edit(context),
                  child: const Text('수정'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(StandingOrderStatus status) {
    final color = status == StandingOrderStatus.active ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _togglePause(BuildContext context) {
    final nextStatus = order.status == StandingOrderStatus.active
        ? StandingOrderStatus.paused
        : StandingOrderStatus.active;
    StandingOrderService.updateStatus(order.id, nextStatus);
  }

  Future<void> _cancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('정기발주 해지'),
        content: const Text('정말 이 정기발주를 해지하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('해지', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      StandingOrderService.updateStatus(order.id, StandingOrderStatus.cancelled);
    }
  }

  void _edit(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StandingOrderFormScreen(partner: partner, order: order),
      ),
    );
  }
}
