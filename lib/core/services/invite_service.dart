import 'package:cloud_functions/cloud_functions.dart';

/// 발급된 초대 코드와 만료 시각.
typedef Invite = ({String code, DateTime expiresAt});

/// 초대 코드 발급(운영자)·소진(거래처 가입) 호출.
class InviteService {
  // Functions가 서울 리전에 배포되므로 리전을 명시해야 호출이 라우팅된다.
  static final FirebaseFunctions _fns =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// 거래처의 새 초대 코드를 발급한다(재발급 시 기존 코드는 서버에서 무효화된다).
  static Future<Invite> issue(String partnerId) async {
    final HttpsCallable callable = _fns.httpsCallable('issueInvite');
    final HttpsCallableResult<dynamic> result =
        await callable.call<dynamic>(<String, dynamic>{'partnerId': partnerId});
    final Map<dynamic, dynamic> data = result.data as Map<dynamic, dynamic>;
    return (
      code: data['code'] as String,
      expiresAt:
          DateTime.fromMillisecondsSinceEpoch(data['expiresAt'] as int),
    );
  }

  /// 초대 코드로 거래처 계정을 생성한다. role='partner'는 서버에서만 설정된다.
  /// 계정 생성만 하고 로그인은 하지 않으므로, 호출부에서 별도로 로그인해야 한다.
  /// 반환값은 연결된 거래처명(가입 완료 안내용).
  static Future<String> redeem({
    required String code,
    required String email,
    required String password,
  }) async {
    final HttpsCallable callable = _fns.httpsCallable('redeemInvite');
    final HttpsCallableResult<dynamic> result =
        await callable.call<dynamic>(<String, dynamic>{
      'code': code,
      'email': email,
      'password': password,
    });
    final Map<dynamic, dynamic> data = result.data as Map<dynamic, dynamic>;
    return data['partnerName'] as String? ?? '';
  }

  /// 초대 코드의 유효성을 미리 확인하고 연결된 거래처명을 가져온다.
  /// IAM 권한 문제를 피하기 위해 이미 잘 작동하는 redeemInvite 함수를 검증 모드로 호출한다.
  static Future<String> check(String code) async {
    final HttpsCallable callable = _fns.httpsCallable('redeemInvite');
    final HttpsCallableResult<dynamic> result =
        await callable.call<dynamic>(<String, dynamic>{
      'code': code,
      'validateOnly': true,
    });
    final Map<dynamic, dynamic> data = result.data as Map<dynamic, dynamic>;
    return data['partnerName'] as String? ?? '';
  }
}
