import 'package:cloud_firestore/cloud_firestore.dart';

/// 즐겨찾기 품목. 단가는 저장하지 않고 이름만 스냅샷한다.
/// 불러올 때 수량만 장바구니에 채우고, 금액은 발주 시점 상품 가격으로 다시 계산한다.
class FavoriteItem {
  const FavoriteItem({
    required this.productId,
    required this.name,
    required this.qty,
  });

  final String productId;
  final String name;
  final int qty;

  factory FavoriteItem.fromMap(Map<String, dynamic> data) {
    return FavoriteItem(
      productId: data['productId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      qty: (data['qty'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'productId': productId,
      'name': name,
      'qty': qty,
    };
  }
}

/// 발주 즐겨찾기. 거래처가 자주 넣는 품목 묶음을 저장해 한 번에 장바구니로 불러온다.
/// partnerId는 규칙 검증(본인 소유 확인)에 쓰이므로 문서에 항상 포함한다.
class Favorite {
  const Favorite({
    required this.id,
    required this.partnerId,
    required this.name,
    required this.items,
    this.createdAt,
  });

  final String id;
  final String partnerId;
  final String name;
  final List<FavoriteItem> items;
  final Timestamp? createdAt;

  factory Favorite.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    final List<dynamic> rawItems = d['items'] as List<dynamic>? ?? <dynamic>[];
    return Favorite(
      id: doc.id,
      partnerId: d['partnerId'] as String? ?? '',
      name: d['name'] as String? ?? '',
      items: rawItems
          .map((dynamic i) => FavoriteItem.fromMap(i as Map<String, dynamic>))
          .toList(),
      createdAt: d['createdAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'partnerId': partnerId,
      'name': name,
      'items': items.map((FavoriteItem i) => i.toMap()).toList(),
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }
}
