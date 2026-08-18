import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/order_status.dart';
import '../../core/models/order.dart' as model;
import '../../core/models/product.dart';
import '../../core/services/order_service.dart';
import '../../core/utils/format.dart';
import 'cart.dart';
import 'partner_home_screen.dart';
import 'widgets/order_badges.dart';
import 'widgets/progress_steps.dart';

/// 거래처 발주 상세. 진행 단계·품목·배송지·메모를 보여주고 재주문을 지원한다.
/// 문서를 실시간 구독하므로 운영자가 상태를 바꾸면 진행 단계가 즉시 이동한다.
class PartnerOrderDetailScreen extends StatelessWidget {
  const PartnerOrderDetailScreen({
    super.key,
    required this.uid,
    required this.orderId,
  });

  final String uid;
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final DocumentReference<Map<String, dynamic>> ref =
        FirebaseFirestore.instance.collection('orders').doc(orderId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (BuildContext context,
          AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snap) {
        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (!snap.data!.exists) {
          return const Scaffold(body: Center(child: Text('삭제된 발주입니다')));
        }
        final model.Order order = model.Order.fromDoc(snap.data!);
        return _DetailView(order: order);
      },
    );
  }
}

class _DetailView extends StatefulWidget {
  const _DetailView({required this.order});

  final model.Order order;

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView> {
  bool _reordering = false;
  bool _requesting = false;

  model.Order get order => widget.order;

  String get _uid {
    final PartnerOrderDetailScreen? parent = context.findAncestorWidgetOfExactType<PartnerOrderDetailScreen>();
    return parent?.uid ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('발주 상세'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
                child: StatusBadge(status: order.status, forPartner: true)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          _headerCard(),
          _itemTable(),
          _paymentSection(),
          if (order.shippingAddress != null) _info('배송지', order.shippingAddress!),
          if (order.memo != null) _info('요청 메모', order.memo!),
          _historySection(),
        ],
      ),
      bottomNavigationBar: _reorderBar(),
    );
  }

  Widget _headerCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F4EF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(order.orderNo,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(
              '${order.source.label} 발주 · '
              '${formatListTime(order.createdAt?.toDate())}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF5F5E5A))),
          if (order.processDate != null) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                const Icon(Icons.event_note, size: 14, color: Color(0xFF8A8880)),
                const SizedBox(width: 4),
                Text(
                  '처리 기준일: ${DateFormat('yyyy년 MM월 dd일').format(order.processDate!)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A18)),
                ),
                if (order.isNextDay) ...<Widget>[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCF0EF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('익일 처리분',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFA32D2D))),
                  ),
                ],
              ],
            ),
          ],
          if (order.desiredDeliveryDate != null) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                const Icon(Icons.calendar_today_outlined,
                    size: 14, color: Color(0xFF185FA5)),
                const SizedBox(width: 4),
                Text(
                  '희망 배송일: ${DateFormat('yyyy년 MM월 dd일').format(order.desiredDeliveryDate!)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF185FA5)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          ProgressSteps(status: order.status),
        ],
      ),
    );
  }

  Widget _itemTable() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('주문 품목 ${order.items.length}건',
              style: const TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
          const SizedBox(height: 6),
          ...order.items.map((model.OrderItem it) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                        child: Text(it.name,
                            style: const TextStyle(fontSize: 13))),
                    Text('× ${it.qty}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF8A8880))),
                    const SizedBox(width: 12),
                    Text(formatWon(it.amount),
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
              )),
          const Divider(),
          Row(
            children: <Widget>[
              const Text('합계',
                  style:
                      TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(formatWon(order.totalAmount),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  /// 결제 상태 + 입금 확인 요청 버튼. (EWOS-44)
  Widget _paymentSection() {
    if (order.status == OrderStatus.canceled) return const SizedBox.shrink();
    if (order.isPaid) {
      return _paymentBanner(Icons.check_circle_outline,
          const Color(0xFF3B7A57), '결제완료', null);
    }
    if (order.isPaymentRequested) {
      return _paymentBanner(Icons.hourglass_top_outlined,
          const Color(0xFF8A6D2D), '입금 확인 요청됨', '운영자 확인을 기다리고 있어요.');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('결제',
              style: TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
          const SizedBox(height: 4),
          const Text('계좌로 입금하셨다면 아래 버튼으로 입금 확인을 요청해 주세요.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _requesting ? null : _requestPayment,
              icon: _requesting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.payments_outlined),
              label: const Text('입금 확인 요청'),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3B7A57)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentBanner(
      IconData icon, Color color, String title, String? sub) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F4EF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color)),
                if (sub != null)
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8A8880))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestPayment() async {
    setState(() => _requesting = true);
    try {
      await OrderService.requestPaymentConfirm(order.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('입금 확인을 요청했습니다. 운영자 확인을 기다려 주세요.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('요청에 실패했습니다. 잠시 후 다시 시도해 주세요.')));
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _historySection() {
    final List<model.StatusHistory> history = order.history;
    if (history.isEmpty) return const SizedBox.shrink();

    // 취소 이력만 찾거나 전체 이력을 보여줄 수 있는데, 
    // 요구사항에 "상태 이력에 취소 시각·주체 기록, 상세 화면에서 확인 가능"이 있으므로
    // 취소 이력이 있으면 강조해서 보여준다.
    final model.StatusHistory? cancelHistory = history.cast<model.StatusHistory?>().firstWhere(
          (h) => h?.status == OrderStatus.canceled,
          orElse: () => null,
        );

    if (cancelHistory == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
              const SizedBox(width: 6),
              const Text('취소 정보',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.red)),
              const Spacer(),
              Text(formatListTime(cancelHistory.at.toDate()),
                  style: const TextStyle(fontSize: 12, color: Colors.red)),
            ],
          ),
          if (cancelHistory.reason != null && cancelHistory.reason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('사유: ${cancelHistory.reason}',
                style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ],
        ],
      ),
    );
  }

  Widget _reorderBar() {
    final bool cancelable = order.status.isCancelable;
    final bool canReorder = order.status != OrderStatus.canceled;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (cancelable) ...<Widget>[
              OutlinedButton(
                onPressed: _reordering ? null : _confirmCancel,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('발주 취소'),
              ),
              const SizedBox(height: 8),
            ],
            if (canReorder)
              OutlinedButton.icon(
                onPressed: _reordering ? null : _reorder,
                icon: _reordering
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: const Text('같은 구성으로 재주문'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancel() async {
    final List<String> reasons = ['오주문', '품목 변경', '배송지 변경', '단순 변심', '기타'];
    String? selectedReason = reasons[0];

    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('발주를 취소하시겠습니까?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('취소된 발주는 되돌릴 수 없습니다. 수정을 원하시면 취소 후 다시 발주해 주세요.'),
              const SizedBox(height: 20),
              const Text('취소 사유 선택',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...reasons.map((r) => RadioListTile<String>(
                    title: Text(r, style: const TextStyle(fontSize: 14)),
                    value: r,
                    groupValue: selectedReason,
                    onChanged: (val) => setDialogState(() => selectedReason = val),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  )),
            ],
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('아니요')),
            TextButton(
              onPressed: () => Navigator.pop(context, selectedReason),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('취소합니다'),
            ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;

    try {
      setState(() => _reordering = true);
      await OrderService.cancelOrder(
        orderId: order.id,
        uid: _uid,
        reason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('발주가 취소되었습니다.')));
      }
    } catch (e) {
      if (mounted) {
        String message = e.toString();
        if (message.contains('permission-denied')) {
          message = '취소 권한이 없거나 이미 운영자가 처리를 시작했습니다.';
        } else if (message.contains('OrderSubmitException')) {
          // 커스텀 예외는 메시지만 추출 (예: "OrderSubmitException: 메시지" -> "메시지")
          message = message.replaceFirst('OrderSubmitException: ', '');
          message = message.replaceFirst('Exception: ', '');
        } else {
          message = '알 수 없는 오류가 발생했습니다: $message';
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  /// 같은 품목·수량을 장바구니에 담고 발주 등록 탭으로 이동한다.
  /// 발주 중지·삭제된 품목은 제외하고 안내한다.
  Future<void> _reorder() async {
    setState(() => _reordering = true);
    try {
      final List<String> ids =
          order.items.map((model.OrderItem it) => it.productId).toList();
      final List<Product> products = await OrderService.fetchProducts(ids);
      final Map<String, Product> byId = <String, Product>{
        for (final Product p in products) p.id: p,
      };
      final List<String> excluded = <String>[];
      Cart.clear();
      for (final model.OrderItem it in order.items) {
        final Product? p = byId[it.productId];
        if (p == null || !p.enabled) {
          excluded.add(it.name);
        } else {
          Cart.setQty(p.id, it.qty);
        }
      }
      if (!mounted) return;
      if (excluded.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${excluded.join(', ')}은(는) 현재 발주할 수 없어 제외했습니다')));
      }
      PartnerHome.tab.value = 0; // 발주 등록 탭
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _reordering = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('재주문 준비에 실패했습니다')));
      }
    }
  }
}
