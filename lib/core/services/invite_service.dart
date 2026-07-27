import 'package:cloud_functions/cloud_functions.dart';

/// 발급된 초대 코드와 만료 시각.
typedef Invite = ({String code, DateTime expiresAt});

/// 초대 코드 발급 호출. redeem(가입)은 EWOS-26 가입 화면에서 다룬다.
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
}
