import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/models/partner.dart';
import '../../core/models/product.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/order_service.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/product_thumb.dart';
import 'cart.dart';
import 'order_confirm_screen.dart';
import 'standing_order_list_screen.dart';
import 'widgets/favorite_sheet.dart';

/// 거래처 홈 = 발주 등록 화면. 쇼핑이 아니라 반복 발주용이라 수량 입력이 중심이다.
/// products를 실시간 구독하므로 운영자가 품목을 중지하면 즉시 목록에서 빠진다.
class OrderFormScreen extends StatefulWidget {
  const OrderFormScreen({
    super.key,
    required this.uid,
    required this.partner,
  });

  final String uid;
  final Partner partner;

  @override
  State<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends State<OrderFormScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  /// 목록형(row) ↔ 격자형(grid) 보기 전환. 기본은 목록형.
  bool _grid = false;

  /// 마지막으로 구독한 상품 목록. 확인 화면에 넘겨 다시 조회하지 않도록 보관한다.
  List<Product> _latest = <Product>[];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _stream {
    // 정렬은 클라이언트에서 한다. enabled 필터와 orderBy를 함께 쓰면 복합 인덱스가 필요해진다.
    return FirebaseFirestore.instance
        .collection('products')
        .where('enabled', isEqualTo: true)
        .snapshots();
  }

  List<Product> _visible(QuerySnapshot<Map<String, dynamic>>? snap) {
    final List<Product> all =
        (snap?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .map(Product.fromDoc)
            .toList()
      ..sort((Product a, Product b) => a.name.compareTo(b.name));
    if (_query.isEmpty) return all;
    final String q = _query.toLowerCase();
    return all
        .where((Product p) => p.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.partner.name,
                style: const TextStyle(fontSize: 12, color: Color(0xFF5F5E5A))),
            const Text('발주 등록', style: TextStyle(fontSize: 18)),
          ],
        ),
        actions: <Widget>[
          IconButton(
            icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
            tooltip: _grid ? '목록 보기' : '격자 보기',
            onPressed: () => setState(() => _grid = !_grid),
          ),
          IconButton(
            icon: const Icon(Icons.star_outline),
            tooltip: '즐겨찾기',
            onPressed: _openFavorites,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today_outlined),
            tooltip: '정기발주',
            onPressed: _openStandingOrders,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => logout(widget.uid),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const _CutoffBanner(),
          _searchField(),
          Expanded(child: _productList()),
        ],
      ),
      bottomNavigationBar: _SummaryBar(onSubmit: _goToConfirm),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchCtrl,
        decoration: const InputDecoration(
          hintText: '품목 검색',
          prefixIcon: Icon(Icons.search),
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onChanged: (String v) => setState(() => _query = v.trim()),
      ),
    );
  }

  Widget _productList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (BuildContext context,
          AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
        if (snap.hasError) {
          return const Center(child: Text('품목을 불러오지 못했습니다'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        _latest = (snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .map(Product.fromDoc)
            .toList();
        final List<Product> products = _visible(snap.data);
        if (products.isEmpty) {
          return Center(
            child: Text(_query.isEmpty
                ? '발주 가능한 품목이 없습니다'
                : '"$_query" 검색 결과가 없습니다'),
          );
        }
        return _grid ? _gridView(products) : _listView(products);
      },
    );
  }

  Widget _listView(List<Product> products) {
    return ListView.separated(
      itemCount: products.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int i) =>
          _ProductRow(product: products[i]),
    );
  }

  Widget _gridView(List<Product> products) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.66,
      ),
      itemCount: products.length,
      itemBuilder: (BuildContext context, int i) =>
          _ProductCard(product: products[i]),
    );
  }

  /// 즐겨찾기 시트를 연다. 저장에 필요한 상품 이름은 구독 중인 _latest에서 가져온다.
  void _openFavorites() {
    showFavoriteSheet(
      context: context,
      partnerId: widget.partner.id,
      products: _latest,
    );
  }

  void _openStandingOrders() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (BuildContext context) => StandingOrderListScreen(
          partner: widget.partner,
        ),
      ),
    );
  }

  /// 발주 확인 화면(EWOS-12)으로 이동한다.
  void _goToConfirm() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (BuildContext context) => OrderConfirmScreen(
          uid: widget.uid,
          partner: widget.partner,
          products: _latest,
        ),
      ),
    );
  }
}

/// 상단 마감 안내 배너. 1분마다 또는 마감 시간 변경 시 갱신된다.
class _CutoffBanner extends StatefulWidget {
  const _CutoffBanner();

  @override
  State<_CutoffBanner> createState() => _CutoffBannerState();
}

class _CutoffBannerState extends State<_CutoffBanner> {
  Timer? _timer;
  TimeOfDay? _cutoff;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final TimeOfDay next = await OrderService.getCutoffTime();
    if (mounted) setState(() => _cutoff = next);
  }

  @override
  Widget build(BuildContext context) {
    if (_cutoff == null) return const SizedBox.shrink();

    final DateTime now = DateTime.now();
    final DateTime cutoffDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _cutoff!.hour,
      _cutoff!.minute,
    );

    final bool isPassed = now.isAfter(cutoffDateTime);
    final Duration diff = cutoffDateTime.difference(now);

    final String message;
    final Color bgColor;
    final Color textColor;

    if (isPassed) {
      message = '오늘 발주가 마감되었습니다. 지금 주문 시 익일 처리됩니다.';
      bgColor = const Color(0xFFFCF0EF);
      textColor = const Color(0xFFA32D2D);
    } else {
      final int h = diff.inHours;
      final int m = diff.inMinutes % 60;
      message = '오늘 마감까지 ${h > 0 ? '$h시간 ' : ''}$m분 남았습니다.';
      bgColor = const Color(0xFFF5F4EF);
      textColor = const Color(0xFF5F5E5A);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: bgColor,
      child: Row(
        children: <Widget>[
          Icon(isPassed ? Icons.info_outline : Icons.timer_outlined,
              size: 16, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// 품목 한 줄(목록형): 이름·단가 + 수량 스테퍼.
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: <Widget>[
          ProductThumb(imageUrl: product.imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(product.name, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 2),
                Text('${formatWon(product.price)} / 개',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF5F5E5A))),
              ],
            ),
          ),
          _QtyStepper(product: product),
        ],
      ),
    );
  }
}

/// 품목 카드(격자형): 썸네일 위, 이름·단가·수량 스테퍼 아래.
class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFEDECE6)),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(child: ProductThumb(imageUrl: product.imageUrl, size: 72)),
          const SizedBox(height: 8),
          Text(product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 2),
          Text('${formatWon(product.price)} / 개',
              style: const TextStyle(fontSize: 12, color: Color(0xFF5F5E5A))),
          const Spacer(),
          Center(child: _QtyStepper(product: product)),
        ],
      ),
    );
  }
}

/// 수량 스테퍼(-/숫자/+). 숫자를 탭하면 직접 입력. 목록·격자에서 공용.
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: Cart.items,
      builder: (BuildContext context, Map<String, int> items, _) {
        final int qty = items[product.id] ?? 0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: qty > 0 ? () => Cart.add(product.id, -1) : null,
            ),
            InkWell(
              onTap: () => _editQty(context, qty),
              child: Container(
                constraints: const BoxConstraints(minWidth: 36),
                alignment: Alignment.center,
                child: Text(
                  '$qty',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: qty > 0 ? FontWeight.w500 : FontWeight.w400,
                    color: qty > 0 ? null : const Color(0xFF8A8880),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => Cart.add(product.id, 1),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editQty(BuildContext context, int current) async {
    final TextEditingController ctrl =
        TextEditingController(text: current > 0 ? '$current' : '');
    final int? result = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(product.name),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '수량', suffixText: '개'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(ctrl.text.trim()) ?? 0),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (result != null) Cart.setQty(product.id, result);
  }
}

/// 하단 고정 합계 바. 담긴 품목이 없으면 제출 버튼이 비활성이다.
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.onSubmit});

  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: Cart.items,
      builder: (BuildContext context, Map<String, int> items, _) {
        return FutureBuilder<int>(
          future: _totalAmount(items),
          builder: (BuildContext context, AsyncSnapshot<int> snap) =>
              _bar(context, items, snap.data ?? 0),
        );
      },
    );
  }

  /// 담긴 품목의 현재 단가로 합계를 계산한다(제출 시 다시 스냅샷하므로 여기선 표시용).
  Future<int> _totalAmount(Map<String, int> items) async {
    if (items.isEmpty) return 0;
    final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
        .instance
        .collection('products')
        .where(FieldPath.documentId, whereIn: items.keys.take(30).toList())
        .get();
    int total = 0;
    for (final QueryDocumentSnapshot<Map<String, dynamic>> d in snap.docs) {
      final Product p = Product.fromDoc(d);
      total += p.price * (items[p.id] ?? 0);
    }
    return total;
  }

  Widget _bar(BuildContext context, Map<String, int> items, int total) {
    final bool empty = items.isEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('${Cart.lineCount}개 품목 · ${Cart.totalQty}개',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF5F5E5A))),
                const Spacer(),
                Text(formatWon(total),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: empty ? null : onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A18),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('발주 넣기', style: TextStyle(fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
