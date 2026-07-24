import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'fcm_service.dart';

/// 로그아웃. 현재 기기 토큰을 먼저 제거해 이후 푸시 수신을 막은 뒤 세션을 종료한다.
/// 여러 화면에서 호출하므로 app.dart가 아닌 공용 위치에 둔다(순환 import 방지).
///
/// 토큰 제거는 부가 작업이므로 실패하더라도 로그아웃 자체는 반드시 진행한다.
/// (권한·네트워크 문제로 토큰 제거가 막혔을 때 사용자가 로그아웃조차 못 하는 상황을 막는다.)
Future<void> logout(String uid) async {
  try {
    await FcmService.unregisterToken(uid);
  } catch (e) {
    debugPrint('FCM 토큰 제거 실패(로그아웃은 계속 진행): $e');
  }
  await FirebaseAuth.instance.signOut();
}
