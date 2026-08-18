import 'package:flutter/material.dart';

import '../../core/constants/legal_docs.dart';

/// 약관·처리방침 종류.
enum LegalDoc { privacy, terms }

/// 이용약관·개인정보처리방침 표시 화면 (EWOS-41).
/// 가입 화면과 설정에서 공용으로 연다.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});

  final LegalDoc doc;

  String get _title =>
      doc == LegalDoc.privacy ? '개인정보처리방침' : '이용약관';

  String get _body =>
      doc == LegalDoc.privacy ? privacyPolicy : termsOfService;

  /// 지정한 문서를 새 화면으로 연다.
  static Future<void> open(BuildContext context, LegalDoc doc) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LegalScreen(doc: doc)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SelectableText(
            _body,
            style: const TextStyle(
                fontSize: 14, height: 1.6, color: Color(0xFF1C1B1F)),
          ),
        ),
      ),
    );
  }
}
