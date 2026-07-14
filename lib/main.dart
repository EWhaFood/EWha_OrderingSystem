import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
// flutterfire configure 실행 시 자동 생성되는 파일이다.
// 아직 생성 전이면 이 import에서 컴파일 에러가 나는 게 정상이다.
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const EwhaOrderingApp());
}
