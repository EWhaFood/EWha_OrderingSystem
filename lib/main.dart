import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

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

  // Crashlytics: 플러터 프레임워크 에러 캡처
  FlutterError.onError = (FlutterErrorDetails details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };
  // Crashlytics: 플러터 외부(비동기 등) 에러 캡처
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  await FcmService.init();
  runApp(const EwhaOrderingApp());
}
