import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/models/product.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/product_thumb.dart';
import '../orders/cart.dart';
import 'customer_cart_screen.dart';

/// 일반 사용자(B2C) 홈 (EWOS-53). 상품을 담아 장바구니 → 간편결제로 주문한다.
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key, required this.uid});

  final String uid;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  /// 최신 구독 상품(장바구니 합계·상세에 사용).
  List<Product> _products = <Product>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('상품'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () => logout(widget.uid),
          ),
        ],
      ),
      body: _productList(),
      bottomNavigationBar: _cartBar(),
    );
  }

  Widget _productList() {
    final Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('products')
        .where('enabled', isEqualTo: true);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (BuildContext context,
          AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        _products = snap.data!.docs.map(Product.fromDoc).toList()
          ..sort((Product a, Product b) => a.name.compareTo(b.name));
        if (_products.isEmpty) {
          return const Center(child: Text('판매 중인 상품이 없습니다.'));
        }
        return ListView.separated(
          itemCount: _products.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int i) =>
              _ProductRow(product: _products[i]),
        );
      },
    );
  }

  Widget _cartBar() {
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: Cart.items,
      builder: (BuildContext context, Map<String, int> items, _) {
        if (items.isEmpty) return const SizedBox.shrink();
        int total = 0;
        for (final Product p in _products) {
          total += p.price * (items[p.id] ?? 0);
        }
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CustomerCartScreen(
                      uid: widget.uid, products: _products),
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF185FA5),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text('장바구니 ${Cart.lineCount}',
                      style: const TextStyle(fontSize: 15)),
                  Text('${formatWon(total)} · 주문하기',
                      style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 상품 한 줄: 썸네일·이름·가격 + 담기 스테퍼.
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
              ProductThumb(imageUrl: product.imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(product.name, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(formatWon(product.price),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF5F5E5A))),
                  ],
                ),
              ),
              if (qty == 0)
                OutlinedButton(
                  onPressed: () => Cart.add(product.id, 1),
                  child: const Text('담기'),
                )
              else
                Row(
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => Cart.add(product.id, -1),
                    ),
                    Text('$qty', style: const TextStyle(fontSize: 15)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => Cart.add(product.id, 1),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
