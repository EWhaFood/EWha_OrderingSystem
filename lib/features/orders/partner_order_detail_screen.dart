import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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

  model.Order get order => widget.order;

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
          if (order.shippingAddress != null) _info('배송지', order.shippingAddress!),
          if (order.memo != null) _info('요청 메모', order.memo!),
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

  Widget _reorderBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: OutlinedButton.icon(
          onPressed: _reordering ? null : _reorder,
          icon: _reordering
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
          label: const Text('같은 구성으로 재주문'),
        ),
      ),
    );
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
