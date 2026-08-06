import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/order_status.dart';
import '../../core/models/order.dart' as model;
import '../../core/models/partner.dart';
import '../../core/services/order_service.dart';
import '../../core/utils/format.dart';
import 'widgets/order_badges.dart';

/// 운영자 발주 상세. 내용 확인과 상태 변경의 중심 화면.
/// 문서를 실시간 구독하므로 다른 담당자가 처리하면 이 화면도 즉시 갱신된다.
class OperatorOrderDetailScreen extends StatelessWidget {
  const OperatorOrderDetailScreen({
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
        return _DetailView(uid: uid, order: order);
      },
    );
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView({required this.uid, required this.order});

  final String uid;
  final model.Order order;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('발주 상세'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: <Widget>[
                StatusBadge(status: order.status),
                const SizedBox(width: 4),
                SourceBadge(source: order.source),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          _PartnerCard(order: order),
          _itemTable(),
          if (order.desiredDeliveryDate != null)
            _info('희망 배송일',
                '${order.desiredDeliveryDate!.year}.${order.desiredDeliveryDate!.month}.${order.desiredDeliveryDate!.day}'),
          if (order.shippingAddress != null) _info('배송지', order.shippingAddress!),
          if (order.memo != null) _info('거래처 요청', order.memo!),
          _InternalMemo(order: order),
          _HistoryTimeline(history: order.history),
        ],
      ),
      bottomNavigationBar: _ActionBar(uid: uid, order: order),
    );
  }

  Widget _itemTable() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
}

/// 거래처 정보 카드. 연락처를 탭하면 전화 앱으로 연결된다.
class _PartnerCard extends StatelessWidget {
  const _PartnerCard({required this.order});

  final model.Order order;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: order.partnerId == null
          ? null
          : FirebaseFirestore.instance
              .collection('partners')
              .doc(order.partnerId)
              .get(),
      builder: (BuildContext context,
          AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snap) {
        final String? phone = snap.hasData && snap.data!.exists
            ? Partner.fromDoc(snap.data!).phone
            : null;
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
              Text(order.partnerName ?? '미분류',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text('주문번호 ${order.orderNo}',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF5F5E5A))),
              const SizedBox(height: 8),
              _metaRow(phone),
            ],
          ),
        );
      },
    );
  }

  /// 접수 시각과 (있으면) 연락처. 연락처를 탭하면 전화 앱으로 연결된다.
  Widget _metaRow(String? phone) {
    return Row(
      children: <Widget>[
        const Icon(Icons.schedule, size: 14, color: Color(0xFF5F5E5A)),
        const SizedBox(width: 4),
        Text(formatListTime(order.createdAt?.toDate()),
            style: const TextStyle(fontSize: 12, color: Color(0xFF5F5E5A))),
        if (phone != null) ...<Widget>[
          const SizedBox(width: 16),
          InkWell(onTap: () => _call(phone), child: _phoneLabel(phone)),
        ],
      ],
    );
  }

  Widget _phoneLabel(String phone) {
    return Row(
      children: <Widget>[
        const Icon(Icons.phone, size: 14, color: Color(0xFF185FA5)),
        const SizedBox(width: 4),
        Text(phone,
            style: const TextStyle(fontSize: 12, color: Color(0xFF185FA5))),
      ],
    );
  }

  Future<void> _call(String phone) async {
    final Uri uri = Uri(scheme: 'tel', path: phone.replaceAll('-', ''));
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}

/// 운영자 전용 내부 메모. 거래처 앱에는 노출되지 않는다.
class _InternalMemo extends StatefulWidget {
  const _InternalMemo({required this.order});

  final model.Order order;

  @override
  State<_InternalMemo> createState() => _InternalMemoState();
}

class _InternalMemoState extends State<_InternalMemo> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.order.internalMemo ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await OrderService.saveInternalMemo(widget.order.id, _ctrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('내부 메모를 저장했습니다')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장에 실패했습니다')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('내부 메모 (거래처에 보이지 않음)',
              style: TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
          const SizedBox(height: 4),
          TextField(
            controller: _ctrl,
            maxLines: 2,
            enabled: !_saving,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.save_outlined, size: 20),
                onPressed: _saving ? null : _save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 처리 이력 타임라인. 누가 언제 어떤 상태로 바꿨는지 순서대로 보여준다.
class _HistoryTimeline extends StatelessWidget {
  const _HistoryTimeline({required this.history});

  final List<model.StatusHistory> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('처리 이력',
              style: TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
          const SizedBox(height: 6),
          ...history.map((model.StatusHistory h) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    StatusBadge(status: h.status),
                    const SizedBox(width: 8),
                    Text(_when(h.at.toDate()),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF5F5E5A))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  String _when(DateTime t) {
    return '${t.month}.${t.day} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}

/// 하단 상태 변경 액션. 현재 상태에서 허용된 전이만 버튼으로 노출한다.
class _ActionBar extends StatefulWidget {
  const _ActionBar({required this.uid, required this.order});

  final String uid;
  final model.Order order;

  @override
  State<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends State<_ActionBar> {
  bool _busy = false;

  /// 전이별 버튼 문구. 운영자가 무엇을 하는지가 드러나게 동사형으로 쓴다.
  String _label(OrderStatus next) {
    switch (next) {
      case OrderStatus.processing:
        return '발주 확인 처리';
      case OrderStatus.shipping:
        return '배송 시작';
      case OrderStatus.done:
        return '배송 완료 처리';
      case OrderStatus.hold:
        return '보류';
      case OrderStatus.newOrder:
        return '보류 해제';
      case OrderStatus.canceled:
        return '취소됨';
    }
  }

  Future<void> _change(OrderStatus next) async {
    setState(() => _busy = true);
    try {
      await OrderService.changeStatus(
        orderId: widget.order.id,
        next: next,
        uid: widget.uid,
      );
    } on OrderSubmitException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('상태 변경에 실패했습니다. 네트워크를 확인해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<OrderStatus> allowed = widget.order.status.allowedTransitions;
    if (allowed.isEmpty) {
      final String msg = widget.order.status == OrderStatus.canceled
          ? '취소된 발주입니다'
          : '처리 완료된 발주입니다';
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF8A8880))),
        ),
      );
    }
    // 보류는 부수 액션이라 왼쪽에 작게, 주 전이는 오른쪽에 강조해 배치한다.
    final bool hasHold = allowed.contains(OrderStatus.hold);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: <Widget>[
            if (hasHold) ...<Widget>[
              Expanded(child: _secondaryButton(OrderStatus.hold)),
              const SizedBox(width: 8),
            ],
            ...allowed
                .where((OrderStatus s) => s != OrderStatus.hold)
                .map((OrderStatus s) =>
                    Expanded(flex: 2, child: _primaryButton(s))),
          ],
        ),
      ),
    );
  }

  Widget _secondaryButton(OrderStatus next) {
    return OutlinedButton(
      onPressed: _busy ? null : () => _change(next),
      child: Text(_label(next)),
    );
  }

  Widget _primaryButton(OrderStatus next) {
    return FilledButton(
      onPressed: _busy ? null : () => _change(next),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF1A1A18),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: _busy
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : Text(_label(next)),
    );
  }
}
