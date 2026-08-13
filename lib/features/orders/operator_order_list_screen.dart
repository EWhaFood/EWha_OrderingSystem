import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/constants/order_status.dart';
import '../../core/models/order.dart' as model;
import '../../core/services/auth_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/utils/format.dart';
import '../notifications/notification_list_screen.dart';
import '../partners/partner_management_screen.dart';
import '../products/product_management_screen.dart';
import '../settings/admin_settings_screen.dart';
import 'operator_order_detail_screen.dart';
import 'widgets/order_badges.dart';

/// 운영자 홈. 앱·카페24 모든 채널의 발주를 한 목록에서 실시간으로 본다.
/// 목록은 스트림 구독이라 거래처가 발주를 넣으면 새로고침 없이 최상단에 나타난다.
class OperatorOrderListScreen extends StatefulWidget {
  const OperatorOrderListScreen({super.key, required this.uid});

  final String uid;

  @override
  State<OperatorOrderListScreen> createState() =>
      _OperatorOrderListScreenState();
}

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: NotificationService.watchUnreadCount(uid),
      builder: (context, snap) {
        final count = snap.data ?? 0;
        return IconButton(
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text('$count'),
            child: const Icon(Icons.notifications_outlined),
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NotificationListScreen(uid: uid, isOperator: true),
            ),
          ),
        );
      },
    );
  }
}

class _OperatorOrderListScreenState extends State<OperatorOrderListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  /// null이면 전체 보기.
  OrderStatus? _filter;
  String _query = '';

  /// 무한 스크롤: 처음 30건을 받고 바닥에 닿을 때마다 늘린다.
  int _limit = 30;
  bool _isFetchingMore = false;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _ordersStream;

  @override
  void initState() {
    super.initState();
    _updateStream();
    _scrollCtrl.addListener(_onScroll);
  }

  void _updateStream() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('orders')
        .orderBy('desiredDeliveryDate', descending: false)
        .orderBy('createdAt', descending: true)
        .limit(_limit);
    if (_filter != null) {
      q = FirebaseFirestore.instance
          .collection('orders')
          .where('status', isEqualTo: _filter!.code)
          .orderBy('desiredDeliveryDate', descending: false)
          .orderBy('createdAt', descending: true)
          .limit(_limit);
    }
    setState(() {
      _ordersStream = q.snapshots();
      _isFetchingMore = false;
    });
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients || _isFetchingMore) return;
    final bool nearBottom = _scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200;
    if (nearBottom) {
      _isFetchingMore = true;
      _limit += 30;
      _updateStream();
    }
  }

  /// 상태 필터는 서버 쿼리로, 검색어는 클라이언트에서 거른다.

  List<model.Order> _filtered(List<model.Order> orders) {
    if (_query.isEmpty) return orders;
    final String q = _query.toLowerCase();
    return orders.where((model.Order o) {
      final String partner = (o.partnerName ?? '미분류').toLowerCase();
      return partner.contains(q) || o.orderNo.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('발주 현황'),
        actions: <Widget>[
          _NotificationIcon(uid: widget.uid),
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: '상품 관리',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (BuildContext context) =>
                    const ProductManagementScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.store_outlined),
            tooltip: '거래처 관리',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (BuildContext context) =>
                    const PartnerManagementScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '설정',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (BuildContext context) =>
                    AdminSettingsScreen(uid: widget.uid),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => logout(widget.uid),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _ordersStream,
        builder: (BuildContext context,
            AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
          if (snap.hasError) {
            debugPrint('Error loading orders: ${snap.error}');
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('발주를 불러오지 못했습니다'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _updateStream,
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<model.Order> all =
              snap.data!.docs.map(model.Order.fromDoc).toList();
          return _body(all);
        },
      ),
    );
  }

  Widget _body(List<model.Order> all) {
    final List<model.Order> list = _filtered(all);
    return RefreshIndicator(
      // 스트림이라 자동 갱신되지만, 사용자가 확인차 당길 수 있게 남겨둔다.
      onRefresh: () async => setState(() {}),
      child: ListView(
        controller: _scrollCtrl,
        children: <Widget>[
          _SummaryCards(orders: all),
          _searchField(),
          _filterChips(all),
          if (list.isEmpty) _emptyState() else ...list.map(_orderCard),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        decoration: const InputDecoration(
          hintText: '거래처명 · 주문번호 검색',
          prefixIcon: Icon(Icons.search),
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onChanged: (String v) => setState(() => _query = v.trim()),
      ),
    );
  }

  Widget _filterChips(List<model.Order> all) {
    final int newCount =
        all.where((model.Order o) => o.status == OrderStatus.newOrder).length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          _chip('전체', null),
          _chip('신규${newCount > 0 ? ' $newCount' : ''}', OrderStatus.newOrder),
          _chip('처리중', OrderStatus.processing),
          _chip('배송중', OrderStatus.shipping),
          _chip('완료', OrderStatus.done),
          _chip('보류', OrderStatus.hold),
          _chip('취소', OrderStatus.canceled),
        ],
      ),
    );
  }

  Widget _chip(String label, OrderStatus? status) {
    final bool selected = _filter == status;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) {
          _filter = status;
          _limit = 30; // 필터 변경 시 리미트 초기화
          _updateStream();
        },
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          _query.isNotEmpty
              ? '"$_query" 검색 결과가 없습니다'
              : _filter == null
                  ? '아직 들어온 발주가 없습니다'
                  : '${_filter!.operatorLabel} 상태의 발주가 없습니다',
          style: const TextStyle(color: Color(0xFF8A8880)),
        ),
      ),
    );
  }

  Widget _orderCard(model.Order o) {
    final String desired = o.desiredDeliveryDate != null
        ? '${o.desiredDeliveryDate!.month}/${o.desiredDeliveryDate!.day}'
        : '-';

    return InkWell(
      onTap: () => _openDetail(o),
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
                // 카페24 주문 중 거래처 매핑이 안 된 건은 '미분류'로 구분해 보여준다.
                Text(o.partnerName ?? '미분류',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(width: 6),
                StatusBadge(status: o.status),
                const SizedBox(width: 4),
                SourceBadge(source: o.source),
                const Spacer(),
                Text(formatListTime(o.createdAt?.toDate()),
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF8A8880))),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _meta(Icons.calendar_today_outlined, '희망일: $desired',
                    color: const Color(0xFF185FA5)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_summary(o),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF5F5E5A))),
                ),
                Text(formatWon(o.totalAmount),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: color ?? const Color(0xFF8A8880)),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontSize: 11, color: color ?? const Color(0xFF5F5E5A))),
      ],
    );
  }

  String _summary(model.Order o) {
    if (o.items.isEmpty) return '품목 없음';
    final String first = o.items.first.name;
    return o.items.length > 1 ? '$first 외 ${o.items.length - 1}건' : first;
  }

  void _openDetail(model.Order o) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            OperatorOrderDetailScreen(uid: widget.uid, orderId: o.id),
      ),
    );
  }
}

/// 상단 요약 카드 3개. 화면에 받아둔 목록으로 계산해 추가 조회를 하지 않는다.
class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.orders});

  final List<model.Order> orders;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final int todayNew = orders.where((model.Order o) {
      final DateTime? t = o.createdAt?.toDate();
      return o.status == OrderStatus.newOrder &&
          t != null &&
          t.year == now.year &&
          t.month == now.month &&
          t.day == now.day;
    }).length;
    final int inProgress = orders
        .where((model.Order o) =>
            o.status == OrderStatus.processing ||
            o.status == OrderStatus.shipping)
        .length;
    final int monthTotal = orders.where((model.Order o) {
      final DateTime? t = o.createdAt?.toDate();
      return t != null && t.year == now.year && t.month == now.month;
    }).fold(0, (int sum, model.Order o) => sum + o.totalAmount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: <Widget>[
          _card('오늘 신규', '$todayNew건'),
          const SizedBox(width: 8),
          _card('진행 중', '$inProgress건'),
          const SizedBox(width: 8),
          _card('이번 달', formatWon(monthTotal)),
        ],
      ),
    );
  }

  Widget _card(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F4EF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label,
                style:
                    const TextStyle(fontSize: 11, color: Color(0xFF8A8880))),
            const SizedBox(height: 2),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
