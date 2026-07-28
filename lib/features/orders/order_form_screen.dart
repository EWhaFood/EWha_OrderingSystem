import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/models/partner.dart';
import '../../core/models/product.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/format.dart';
import 'cart.dart';
import 'order_confirm_screen.dart';
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
            icon: const Icon(Icons.star_outline),
            tooltip: '즐겨찾기',
            onPressed: _openFavorites,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => logout(widget.uid),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
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
        return ListView.separated(
          itemCount: products.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int i) =>
              _ProductRow(product: products[i]),
        );
      },
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

/// 품목 한 줄: 이름·단가 + 수량 스테퍼. 수량 숫자를 탭하면 직접 입력할 수 있다.
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: Cart.items,
      builder: (BuildContext context, Map<String, int> items, _) {
        final int qty = items[product.id] ?? 0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
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
              _stepper(context, qty),
            ],
          ),
        );
      },
    );
  }

  Widget _stepper(BuildContext context, int qty) {
    return Row(
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
