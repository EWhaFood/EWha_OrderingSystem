import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/services/fcm_service.dart';
// flutterfire configure 실행 시 자동 생성되는 파일이다.
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // 백그라운드/종료 상태 메시지 핸들러는 runApp 전에 등록해야 한다.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await FcmService.init();
  runApp(const EwhaOrderingApp());
}
