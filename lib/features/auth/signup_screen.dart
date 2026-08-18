import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/invite_service.dart';
import '../legal/legal_screen.dart';

/// 거래처 초대 코드 가입 화면.
/// 1단계: 초대 코드 입력 -> 거래처 확인 다이얼로그
/// 2단계: 이메일/비밀번호 설정 -> 가입 완료 -> 자동 로그인
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

enum SignupStep { code, info }

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _pwCtrl = TextEditingController();
  final TextEditingController _pw2Ctrl = TextEditingController();

  SignupStep _step = SignupStep.code;
  String? _partnerName;
  bool _loading = false;
  bool _agreed = false; // 약관·개인정보처리방침 필수 동의
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _pw2Ctrl.dispose();
    super.dispose();
  }

  /// 1단계: 코드 유효성 검사 및 거래처명 확인
  Future<void> _checkCode() async {
    final String code = _codeCtrl.text.trim().toUpperCase(); // 대문자로 변환
    if (code.isEmpty) {
      setState(() => _error = '초대 코드를 입력하세요');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final String name = await InviteService.check(code);
      if (!mounted) return;

      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('거래처 확인'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('[$name]',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              const Text('위 거래처가 맞습니까?\n맞다면 가입 정보를 입력해 주세요.'),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('다시 입력'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A18)),
              child: const Text('예, 맞습니다'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        setState(() {
          _partnerName = name;
          _step = SignupStep.info;
        });
      }
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = _messageForFn(e));
    } catch (e) {
      setState(() => _error = '확인 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 2단계 최종 제출
  Future<void> _submit() async {
    final String code = _codeCtrl.text.trim().toUpperCase();
    final String email = _emailCtrl.text.trim();
    final String pw = _pwCtrl.text;
    final String pw2 = _pw2Ctrl.text;

    // 이메일 및 비밀번호 유효성 검사
    if (email.isEmpty || pw.isEmpty) {
      setState(() => _error = '모든 항목을 입력하세요');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = '이메일 형식이 올바르지 않습니다');
      return;
    }
    if (pw.length < 6) {
      setState(() => _error = '비밀번호는 6자 이상이어야 합니다');
      return;
    }
    if (pw != pw2) {
      setState(() => _error = '비밀번호가 일치하지 않습니다');
      return;
    }
    if (!_agreed) {
      setState(() => _error = '이용약관과 개인정보처리방침에 동의해야 가입할 수 있습니다');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await InviteService.redeem(code: code, email: email, password: pw);
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: pw);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_partnerName 가입이 완료되었습니다')),
      );
      Navigator.of(context).pop();
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = _messageForFn(e));
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _messageForAuth(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 서버 에러 메시지 한글화 (사진 속 요구사항 반영)
  String _messageForFn(FirebaseFunctionsException e) {
    final String? server = e.message;
    if (server != null && server.isNotEmpty) return server;
    switch (e.code) {
      case 'permission-denied':
        return '서버 접근 권한이 없습니다. 관리자에게 문의하세요.';
      case 'not-found':
        return '존재하지 않는 초대 코드입니다';
      case 'already-exists':
        return '이미 사용된 코드이거나 가입된 이메일입니다';
      case 'deadline-exceeded':
        return '만료된 초대 코드입니다. 운영자에게 재발급을 요청하세요.';
      default:
        return '처리에 실패했습니다 (${e.code})';
    }
  }

  String _messageForAuth(String code) {
    switch (code) {
      case 'network-request-failed':
        return '네트워크 연결을 확인하세요';
      default:
        return '가입은 됐지만 로그인에 실패했습니다. 로그인 화면에서 다시 시도하세요';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('초대 코드로 가입'),
        leading: _step == SignupStep.info
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _step = SignupStep.code),
              )
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_step == SignupStep.code) ..._buildCodeStep(),
                if (_step == SignupStep.info) ..._buildInfoStep(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCodeStep() {
    return <Widget>[
      const Text(
        '운영자에게 받은 초대 코드를 입력해 주세요.',
        style: TextStyle(fontSize: 14, color: Color(0xFF6B6A64)),
      ),
      const SizedBox(height: 24),
      _field(_codeCtrl, '초대 코드', TextInputType.text, false, caps: true), // 대문자 자동변환 적용
      if (_error != null) _errorText(),
      const SizedBox(height: 24),
      _submitButton('코드 확인', _checkCode),
    ];
  }

  List<Widget> _buildInfoStep() {
    return <Widget>[
      Text(
        '$_partnerName 계정 정보를 설정합니다.',
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A18)),
      ),
      const SizedBox(height: 8),
      const Text(
        '앞으로 로그인할 때 사용할 이메일과 비밀번호를 입력해 주세요.',
        style: TextStyle(fontSize: 13, color: Color(0xFF6B6A64)),
      ),
      const SizedBox(height: 24),
      _field(_emailCtrl, '이메일 주소', TextInputType.emailAddress, false),
      const SizedBox(height: 12),
      _field(_pwCtrl, '비밀번호 (6자 이상)', TextInputType.text, true),
      const SizedBox(height: 12),
      _field(_pw2Ctrl, '비밀번호 확인', TextInputType.text, true),
      const SizedBox(height: 8),
      _consent(),
      if (_error != null) _errorText(),
      const SizedBox(height: 24),
      _submitButton('가입 완료', _submit),
    ];
  }

  /// 필수 동의 행: 체크박스 + 약관/처리방침 열람 링크.
  Widget _consent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Checkbox(
          value: _agreed,
          onChanged:
              _loading ? null : (bool? v) => setState(() => _agreed = v ?? false),
        ),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _legalLink('이용약관', LegalDoc.terms),
              const Text(' 및 '),
              _legalLink('개인정보처리방침', LegalDoc.privacy),
              const Text('에 동의합니다 (필수)'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legalLink(String label, LegalDoc doc) {
    return GestureDetector(
      onTap: () => LegalScreen.open(context, doc),
      child: Text(label,
          style: const TextStyle(
              color: Color(0xFF3B7A57),
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _field(TextEditingController ctrl, String label, TextInputType type,
      bool obscure, {bool caps = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      obscureText: obscure,
      enabled: !_loading,
      textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none, // 대문자 자동변환
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _errorText() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(_error!,
          style: const TextStyle(color: Color(0xFFA32D2D), fontSize: 13)),
    );
  }

  Widget _submitButton(String label, VoidCallback onPressed) {
    return FilledButton(
      onPressed: _loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF1A1A18),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: _loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : Text(label,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}
