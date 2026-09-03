import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../legal/legal_screen.dart';
import 'signup_screen.dart';

/// 운영자·거래처 공통 로그인 화면. 로그인 성공 후 라우팅은 AuthGate가 role로 분기한다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _pwCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final String email = _emailCtrl.text.trim();
    final String pw = _pwCtrl.text;
    if (email.isEmpty || pw.isEmpty) {
      setState(() => _error = '이메일과 비밀번호를 입력하세요');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: pw);
      // 성공 시 AuthGate가 자동으로 홈으로 전환한다.
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _messageFor(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final String email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = '재설정할 이메일을 먼저 입력하세요');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$email 로 재설정 메일을 보냈습니다')),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _messageFor(e.code));
    }
  }

  /// 구글 로그인/가입 (EWOS-53). 가입 전 약관·개인정보 동의를 먼저 받는다(EWOS-41).
  Future<void> _googleSignIn() async {
    final bool agreed = await _confirmLegalConsent();
    if (!agreed) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await signInWithGoogle();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _messageFor(e.code));
    } catch (_) {
      setState(() => _error = '구글 로그인에 실패했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 구글 가입 전 약관·개인정보 동의 시트. "동의하고 계속"을 누르면 true.
  Future<bool> _confirmLegalConsent() async {
    final bool? ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('약관 동의',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _legalLink(ctx, '이용약관', LegalDoc.terms),
                  const Text(' 및 '),
                  _legalLink(ctx, '개인정보처리방침', LegalDoc.privacy),
                  const Text('에 동의하고 계속합니다. (필수)'),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1A1A18)),
                      child: const Text('동의하고 계속'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return ok ?? false;
  }

  Widget _legalLink(BuildContext ctx, String label, LegalDoc doc) {
    return GestureDetector(
      onTap: () => LegalScreen.open(ctx, doc),
      child: Text(label,
          style: const TextStyle(
              color: Color(0xFF3B7A57),
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.w600)),
    );
  }

  void _goToSignup() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SignupScreen()),
    );
  }

  String _messageFor(String code) {
    switch (code) {
      case 'invalid-email':
        return '이메일 형식이 올바르지 않습니다';
      case 'user-disabled':
        return '비활성화된 계정입니다. 관리자에게 문의하세요';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return '이메일 또는 비밀번호가 올바르지 않습니다';
      case 'network-request-failed':
        return '네트워크 연결을 확인하세요';
      default:
        return '로그인에 실패했습니다 ($code)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _header(),
                const SizedBox(height: 28),
                _field(_emailCtrl, '이메일', TextInputType.emailAddress, false),
                const SizedBox(height: 12),
                _field(_pwCtrl, '비밀번호', TextInputType.text, true),
                if (_error != null) _errorText(),
                const SizedBox(height: 20),
                _loginButton(),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading ? null : _resetPassword,
                  child: const Text('비밀번호를 잊으셨나요?'),
                ),
                const Divider(height: 24),
                const Text('일반 사용자',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _googleSignIn,
                  icon: const Icon(Icons.g_mobiledata, size: 28),
                  label: const Text('구글로 시작하기'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('거래처(업체)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _loading ? null : _goToSignup,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('초대 코드로 가입'),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _legalLink(context, '개인정보처리방침', LegalDoc.privacy),
                    const Text('   ·   ',
                        style: TextStyle(color: Color(0xFF8A8880))),
                    _legalLink(context, '이용약관', LegalDoc.terms),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      children: <Widget>[
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.list_alt, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 12),
        const Text('이화 발주',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
      ],
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

  Widget _loginButton() {
    return FilledButton(
      onPressed: _loading ? null : _login,
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
          : const Text('로그인', style: TextStyle(fontSize: 15)),
    );
  }
}
