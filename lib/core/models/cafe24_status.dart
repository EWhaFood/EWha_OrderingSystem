import 'package:cloud_firestore/cloud_firestore.dart';

/// 카페24 몰 하나의 연동 상태. Functions가 cafe24Status/{mallId}에 기록하며
/// 시크릿(토큰)은 담기지 않고, 운영자 화면에 보여줄 요약만 담긴다.
class Cafe24Status {
  const Cafe24Status({
    required this.mallId,
    required this.connected,
    this.accessExpiresAt,
    this.lastOrderSync,
    this.lastProductSync,
    this.productCount,
  });

  final String mallId;
  final bool connected;

  /// Access Token 만료 시각. 지났거나 임박하면 재인증이 필요할 수 있다.
  final Timestamp? accessExpiresAt;
  final Timestamp? lastOrderSync;
  final Timestamp? lastProductSync;
  final int? productCount;

  /// 토큰이 이미 만료됐는지. 자동 갱신(60분)으로 대개 유지되지만 만료면 경고한다.
  bool get tokenExpired =>
      accessExpiresAt != null &&
      accessExpiresAt!.toDate().isBefore(DateTime.now());

  factory Cafe24Status.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return Cafe24Status(
      mallId: d['mallId'] as String? ?? doc.id,
      connected: d['connected'] as bool? ?? false,
      accessExpiresAt: d['accessExpiresAt'] as Timestamp?,
      lastOrderSync: d['lastOrderSync'] as Timestamp?,
      lastProductSync: d['lastProductSync'] as Timestamp?,
      productCount: (d['productCount'] as num?)?.toInt(),
    );
  }
}
