import 'package:cloud_firestore/cloud_firestore.dart';

/// 카페24에서 동기화된 상품. 앱은 이 컬렉션만 읽고 카페24를 직접 호출하지 않는다.
/// enabled는 운영자가 수동 관리하며 동기화가 덮어쓰지 않는다.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.price,
    this.cafe24ProductNo,
    this.imageUrl,
    this.enabled = true,
    this.stock,
    this.updatedAt,
  });

  final String id;
  final String name;
  final int price;

  /// 카페24 상품 번호. 동기화 매핑 키.
  final String? cafe24ProductNo;
  final String? imageUrl;

  /// 발주 가능 여부. false면 거래처 발주 등록 목록에서 제외된다.
  final bool enabled;
  final int? stock;
  final Timestamp? updatedAt;

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    return Product(
      id: doc.id,
      name: data['name'] as String? ?? '',
      price: (data['price'] as num?)?.toInt() ?? 0,
      cafe24ProductNo: data['cafe24ProductNo'] as String?,
      imageUrl: data['imageUrl'] as String?,
      enabled: data['enabled'] as bool? ?? true,
      stock: (data['stock'] as num?)?.toInt(),
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'price': price,
      'cafe24ProductNo': cafe24ProductNo,
      'imageUrl': imageUrl,
      'enabled': enabled,
      'stock': stock,
      'updatedAt': updatedAt ?? FieldValue.serverTimestamp(),
    };
  }
}
