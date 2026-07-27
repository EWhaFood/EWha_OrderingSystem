import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/invite_service.dart';

/// 거래처 초대 코드 가입 화면. redeemInvite로 계정을 만든 뒤 곧바로 로그인한다.
/// 로그인이 되면 AuthGate가 role='partner'로 자동 라우팅한다.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _pwCtrl = TextEditingController();
  final TextEditingController _pw2Ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _pw2Ctrl.dispose();
    super.dispose();
  }

  /// 클라이언트 1차 검증. null이면 통과.
  String? _validate(String code, String email, String pw, String pw2) {
    if (code.isEmpty || email.isEmpty || pw.isEmpty) return '모든 항목을 입력하세요';
    if (!email.contains('@')) return '이메일 형식이 올바르지 않습니다';
    if (pw.length < 6) return '비밀번호는 6자 이상이어야 합니다';
    if (pw != pw2) return '비밀번호가 일치하지 않습니다';
    return null;
  }

  Future<void> _submit() async {
    final String code = _codeCtrl.text.trim();
    final String email = _emailCtrl.text.trim();
    final String pw = _pwCtrl.text;
    final String? err = _validate(code, email, pw, _pw2Ctrl.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final String partnerName =
          await InviteService.redeem(code: code, email: email, password: pw);
      // 서버는 계정만 만든다. 로그인하면 AuthGate가 홈으로 전환한다.
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: pw);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$partnerName 가입이 완료되었습니다')),
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

  /// 서버 HttpsError 메시지는 이미 한국어라 우선 노출하고, 없으면 코드로 대체한다.
  String _messageForFn(FirebaseFunctionsException e) {
    final String? server = e.message;
    if (server != null && server.isNotEmpty) return server;
    switch (e.code) {
      case 'not-found':
        return '존재하지 않는 초대 코드입니다';
      case 'already-exists':
        return '이미 사용된 코드이거나 가입된 이메일입니다';
      case 'deadline-exceeded':
        return '만료된 초대 코드입니다';
      default:
        return '가입에 실패했습니다 (${e.code})';
    }
  }

  String _messageForAuth(String code) {
    switch (code) {
      case 'network-request-failed':
        return '네트워크 연결을 확인하세요';
      default:
        // 계정은 만들어졌으나 자동 로그인만 실패한 경우. 로그인 화면에서 재시도 가능.
        return '가입은 됐지만 로그인에 실패했습니다. 로그인 화면에서 다시 시도하세요';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('초대 코드로 가입')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _guide(),
                const SizedBox(height: 20),
                _field(_codeCtrl, '초대 코드', TextInputType.text, false),
                const SizedBox(height: 12),
                _field(_emailCtrl, '이메일', TextInputType.emailAddress, false),
                const SizedBox(height: 12),
                _field(_pwCtrl, '비밀번호 (6자 이상)', TextInputType.text, true),
                const SizedBox(height: 12),
                _field(_pw2Ctrl, '비밀번호 확인', TextInputType.text, true),
                if (_error != null) _errorText(),
                const SizedBox(height: 20),
                _submitButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _guide() {
    return const Text(
      '운영자에게 받은 초대 코드로 가입하세요.\n가입 후 바로 발주를 넣을 수 있습니다.',
      style: TextStyle(fontSize: 13, color: Color(0xFF6B6A64), height: 1.5),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      TextInputType type, bool obscure) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      obscureText: obscure,
      enabled: !_loading,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
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

  Widget _submitButton() {
    return FilledButton(
      onPressed: _loading ? null : _submit,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF1A1A18),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: _loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : const Text('가입하기', style: TextStyle(fontSize: 15)),
    );
  }
}
