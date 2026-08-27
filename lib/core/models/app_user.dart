import 'package:cloud_firestore/cloud_firestore.dart';

/// 사용자 계정. role로 운영자/거래처를 구분하고, 거래처면 partnerId로 연결한다.
/// role 필드는 클라이언트에서 수정 금지 — Functions만 설정한다.
enum UserRole {
  operator('operator'),
  partner('partner'),
  customer('customer'); // 일반 사용자(B2C, 구글 셀프가입) — EWOS-53

  const UserRole(this.code);

  final String code;

  static UserRole fromCode(String code) {
    return UserRole.values.firstWhere(
      (UserRole r) => r.code == code,
      orElse: () => UserRole.partner,
    );
  }
}

class AppUser {
  const AppUser({
    required this.uid,
    required this.role,
    required this.email,
    this.partnerId,
    this.fcmTokens = const <String>[],
  });

  final String uid;
  final UserRole role;
  final String email;

  /// role이 partner일 때만 존재. 해당 거래처 문서 ID.
  final String? partnerId;

  /// 로그인한 기기별 FCM 토큰 목록.
  final List<String> fcmTokens;

  bool get isOperator => role == UserRole.operator;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    return AppUser(
      uid: doc.id,
      role: UserRole.fromCode(data['role'] as String? ?? 'partner'),
      email: data['email'] as String? ?? '',
      partnerId: data['partnerId'] as String?,
      fcmTokens: List<String>.from(data['fcmTokens'] as List<dynamic>? ?? <dynamic>[]),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'role': role.code,
      'email': email,
      'partnerId': partnerId,
      'fcmTokens': fcmTokens,
    };
  }
}
