import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/favorite.dart';
import '../models/product.dart';

/// 즐겨찾기 저장을 막아야 하는 상황(빈 목록 등)을 화면에 전달한다.
class FavoriteException implements Exception {
  FavoriteException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 발주 즐겨찾기 저장·조회·삭제. OrderService와 동일한 static 서비스 패턴을 따른다.
class FavoriteService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// 거래처 본인의 즐겨찾기 목록을 실시간 구독한다.
  /// 정렬은 클라이언트에서 한다(partnerId 필터 + orderBy 복합 인덱스를 피하기 위함).
  static Stream<List<Favorite>> watch(String partnerId) {
    return _db
        .collection('favorites')
        .where('partnerId', isEqualTo: partnerId)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) => _sorted(snap));
  }

  /// createdAt 내림차순 정렬. serverTimestamp 반영 전(null)인 문서는 맨 앞에 둔다.
  static List<Favorite> _sorted(QuerySnapshot<Map<String, dynamic>> snap) {
    final List<Favorite> list =
        snap.docs.map(Favorite.fromDoc).toList();
    list.sort((Favorite a, Favorite b) {
      final Timestamp? at = a.createdAt;
      final Timestamp? bt = b.createdAt;
      if (at == null) return bt == null ? 0 : -1;
      if (bt == null) return 1;
      return bt.compareTo(at);
    });
    return list;
  }

  /// 현재 담긴 수량(qtys)과 상품 목록(products)으로 즐겨찾기를 저장한다.
  /// 단가는 저장하지 않고 이름만 스냅샷한다. 담긴 품목이 없으면 예외를 던진다.
  static Future<void> save({
    required String partnerId,
    required String name,
    required Map<String, int> qtys,
    required List<Product> products,
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) throw FavoriteException('즐겨찾기 이름을 입력해주세요.');
    final List<FavoriteItem> items = _buildItems(qtys, products);
    if (items.isEmpty) throw FavoriteException('담긴 품목이 없습니다.');
    final Favorite favorite = Favorite(
      id: '',
      partnerId: partnerId,
      name: trimmed,
      items: items,
    );
    await _db.collection('favorites').add(favorite.toMap());
  }

  /// qtys와 products를 맞춰 FavoriteItem 목록을 만든다. 수량 0 이하는 제외한다.
  static List<FavoriteItem> _buildItems(
    Map<String, int> qtys,
    List<Product> products,
  ) {
    final Map<String, Product> byId = <String, Product>{
      for (final Product p in products) p.id: p,
    };
    final List<FavoriteItem> items = <FavoriteItem>[];
    for (final MapEntry<String, int> e in qtys.entries) {
      if (e.value <= 0) continue;
      final Product? p = byId[e.key];
      if (p == null) continue;
      items.add(FavoriteItem(productId: p.id, name: p.name, qty: e.value));
    }
    return items;
  }

  /// 즐겨찾기 문서를 삭제한다. 규칙상 거래처 본인 문서만 삭제된다.
  static Future<void> remove(String favId) async {
    await _db.collection('favorites').doc(favId).delete();
  }
}
