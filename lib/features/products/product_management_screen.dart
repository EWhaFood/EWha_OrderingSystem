import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/models/cafe24_status.dart';
import '../../core/models/product.dart';
import '../../core/services/cafe24_service.dart';
import '../../core/utils/format.dart';

/// 운영자 상품 관리 (EWOS-23). 카페24 동기화 상태·수동 동기화 + 품목별 발주 가능/불가.
/// products는 카페24에서 복제되며, enabled(발주 가능)만 이 화면에서 운영자가 관리한다.
class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  State<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen> {
  bool _syncing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final SyncResult r = await Cafe24Service.syncProducts();
      _toast(r.malls == 0
          ? '연동된 카페24 몰이 없습니다'
          : '상품 ${r.products}건 동기화 완료');
    } on FirebaseFunctionsException catch (e) {
      _toast(e.message ?? '동기화에 실패했습니다');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('상품 관리'),
        actions: <Widget>[
          IconButton(
            icon: _syncing
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            tooltip: '카페24 상품 동기화',
            onPressed: _syncing ? null : _sync,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const _StatusSection(),
          const Divider(height: 1),
          Expanded(child: _productList()),
        ],
      ),
    );
  }

  Widget _productList() {
    final Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collection('products').orderBy('name');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (BuildContext context,
          AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final List<Product> products =
            snap.data!.docs.map(Product.fromDoc).toList();
        if (products.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('동기화된 상품이 없습니다. 위 새로고침으로 카페24 상품을 가져오세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF8A8880))),
            ),
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
}

/// 카페24 연동 상태 카드들. cafe24Status 컬렉션을 실시간 구독한다.
class _StatusSection extends StatelessWidget {
  const _StatusSection();

  @override
  Widget build(BuildContext context) {
    final Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collection('cafe24Status');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (BuildContext context,
          AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
        if (!snap.hasData) return const SizedBox(height: 4);
        final List<Cafe24Status> list =
            snap.data!.docs.map(Cafe24Status.fromDoc).toList();
        if (list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('연동된 카페24 몰이 없습니다. 몰에 앱을 설치해 연동하세요.',
                style: TextStyle(fontSize: 13, color: Color(0xFF8A8880))),
          );
        }
        return Column(children: list.map((Cafe24Status s) => _card(s)).toList());
      },
    );
  }

  Widget _card(Cafe24Status s) {
    final bool warn = !s.connected || s.tokenExpired;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warn ? const Color(0xFFFCF0EF) : const Color(0xFFF5F4EF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(warn ? Icons.error_outline : Icons.check_circle_outline,
                  size: 16,
                  color: warn ? const Color(0xFFA32D2D)
                      : const Color(0xFF3B7A57)),
              const SizedBox(width: 6),
              Text(s.mallId,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(width: 6),
              Text(
                warn ? (s.tokenExpired ? '토큰 만료' : '연동 끊김') : '연동 정상',
                style: TextStyle(
                    fontSize: 12,
                    color: warn ? const Color(0xFFA32D2D)
                        : const Color(0xFF3B7A57)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _line('상품 동기화', s.lastProductSync,
              suffix: s.productCount != null ? ' · ${s.productCount}건' : ''),
          _line('주문 동기화', s.lastOrderSync),
        ],
      ),
    );
  }

  Widget _line(String label, Timestamp? at, {String suffix = ''}) {
    final String when =
        at == null ? '이력 없음' : '${formatListTime(at.toDate())}$suffix';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text('$label: $when',
          style: const TextStyle(fontSize: 12, color: Color(0xFF5F5E5A))),
    );
  }
}

/// 상품 한 행: 이름·가격 + 발주 가능 토글. 토글은 products/{id}.enabled만 바꾼다.
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final Product product;

  Future<void> _toggle(bool next) async {
    await FirebaseFirestore.instance
        .collection('products')
        .doc(product.id)
        .update(<String, dynamic>{'enabled': next});
  }

  @override
  Widget build(BuildContext context) {
    final Product p = product;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(p.name,
                    style: TextStyle(
                        fontSize: 14,
                        color: p.enabled
                            ? const Color(0xFF1A1A18)
                            : const Color(0xFF8A8880))),
                const SizedBox(height: 2),
                Text(formatWon(p.price),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF5F5E5A))),
              ],
            ),
          ),
          Text(p.enabled ? '발주 가능' : '발주 중지',
              style: TextStyle(
                  fontSize: 11,
                  color: p.enabled
                      ? const Color(0xFF3B7A57)
                      : const Color(0xFF8A8880))),
          Switch(value: p.enabled, onChanged: _toggle),
        ],
      ),
    );
  }
}
