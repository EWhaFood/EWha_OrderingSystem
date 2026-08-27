import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/models/product.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/product_thumb.dart';

/// 일반 사용자(B2C) 홈 (EWOS-53, Phase 1). 지금은 상품 둘러보기까지.
/// 소비자 주문·간편결제 흐름은 Phase 2에서 붙인다.
class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('상품 둘러보기'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () => logout(uid),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const _Notice(),
          const Divider(height: 1),
          Expanded(child: _productList()),
        ],
      ),
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
        final List<Product> products =
            snap.data!.docs.map(Product.fromDoc).toList()
              ..sort((Product a, Product b) => a.name.compareTo(b.name));
        if (products.isEmpty) {
          return const Center(child: Text('판매 중인 상품이 없습니다.'));
        }
        return ListView.separated(
          itemCount: products.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int i) {
            final Product p = products[i];
            return ListTile(
              leading: ProductThumb(imageUrl: p.imageUrl),
              title: Text(p.name, style: const TextStyle(fontSize: 14)),
              subtitle: Text(formatWon(p.price),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF5F5E5A))),
            );
          },
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF5F4EF),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Text('주문·결제 기능은 곧 제공됩니다. 지금은 상품을 둘러볼 수 있어요.',
          style: TextStyle(fontSize: 12, color: Color(0xFF5F5E5A))),
    );
  }
}
