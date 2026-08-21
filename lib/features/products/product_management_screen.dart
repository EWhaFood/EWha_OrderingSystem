import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/models/cafe24_status.dart';
import '../../core/models/product.dart';
import '../../core/services/cafe24_service.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/product_thumb.dart';

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
  String _searchQuery = '';
  bool _showDisabledOnly = false;
  bool _sortByName = true;

  /// 목록형(row) ↔ 격자형(grid) 보기 전환. 기본은 목록형.
  bool _grid = false;

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
    String displayMsg = msg;
    // 영어 에러 메시지를 사용자 친화적인 한글로 변경
    if (msg.contains('INTERNAL')) {
      displayMsg = '서버 내부 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
    } else if (msg.contains('not-found')) {
      displayMsg = '관련 정보를 찾을 수 없습니다.';
    } else if (msg.contains('permission-denied')) {
      displayMsg = '권한이 없습니다.';
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(displayMsg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('상품 관리'),
        actions: <Widget>[
          IconButton(
            icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
            tooltip: _grid ? '목록 보기' : '격자 보기',
            onPressed: () => setState(() => _grid = !_grid),
          ),
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
          _buildSearchAndFilter(), // [신규] 명세서에 따른 검색 및 필터 UI 추가
          const Divider(height: 1),
          Expanded(child: _productList()),
        ],
      ),
    );
  }

  // 검색창 및 정렬/필터 칩 위젯 빌드
  Widget _buildSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: <Widget>[
          TextField(
            onChanged: (String v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: '상품명 검색',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              // 발주 중지된 상품만 모아보는 필터
              FilterChip(
                label: const Text('중지 품목 모아보기', style: TextStyle(fontSize: 12)),
                selected: _showDisabledOnly,
                onSelected: (bool v) => setState(() => _showDisabledOnly = v),
              ),
              const SizedBox(width: 8),
              // 이름순 정렬 토글 버튼
              ActionChip(
                avatar: Icon(_sortByName ? Icons.sort_by_alpha : Icons.sort, size: 16),
                label: Text(_sortByName ? '이름순' : '기본순', style: const TextStyle(fontSize: 12)),
                onPressed: () => setState(() => _sortByName = !_sortByName),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _productList() {
    Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collection('products');
    
    if (_sortByName) {
      q = q.orderBy('name');
    }
    
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (BuildContext context,
          AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        List<Product> products =
            snap.data!.docs.map(Product.fromDoc).toList();
        
        // 검색 필터링
        if (_searchQuery.isNotEmpty) {
          products = products
              .where((Product p) =>
                  p.name.toLowerCase().contains(_searchQuery.toLowerCase()))
              .toList();
        }
        
        // 중지 품목 필터링
        if (_showDisabledOnly) {
          products = products.where((Product p) => !p.enabled).toList();
        }

        if (products.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('조건에 맞는 상품이 없습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF8A8880))),
            ),
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
        childAspectRatio: 0.64,
      ),
      itemCount: products.length,
      itemBuilder: (BuildContext context, int i) =>
          _ProductCard(product: products[i]),
    );
  }
}

/// products/{id}.enabled만 갱신한다. 목록·격자 카드에서 공용.
Future<void> _setProductEnabled(String id, bool next) {
  return FirebaseFirestore.instance
      .collection('products')
      .doc(id)
      .update(<String, dynamic>{'enabled': next});
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

/// 상품 한 행(목록형): 이름·가격 + 발주 가능 토글.
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final Product p = product;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          ProductThumb(imageUrl: p.imageUrl),
          const SizedBox(width: 12),
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
          Switch(
              value: p.enabled,
              onChanged: (bool v) => _setProductEnabled(p.id, v)),
        ],
      ),
    );
  }
}

/// 상품 카드(격자형): 썸네일 위, 이름·가격·발주 토글 아래.
class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final Product p = product;
    final Color nameColor =
        p.enabled ? const Color(0xFF1A1A18) : const Color(0xFF8A8880);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFEDECE6)),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(child: ProductThumb(imageUrl: p.imageUrl, size: 72)),
          const SizedBox(height: 8),
          Text(p.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: nameColor)),
          const SizedBox(height: 2),
          Text(formatWon(p.price),
              style: const TextStyle(fontSize: 12, color: Color(0xFF5F5E5A))),
          const Spacer(),
          Row(
            children: <Widget>[
              Text(p.enabled ? '발주 가능' : '발주 중지',
                  style: TextStyle(
                      fontSize: 11,
                      color: p.enabled
                          ? const Color(0xFF3B7A57)
                          : const Color(0xFF8A8880))),
              const Spacer(),
              Switch(
                  value: p.enabled,
                  onChanged: (bool v) => _setProductEnabled(p.id, v)),
            ],
          ),
        ],
      ),
    );
  }
}
