import 'package:flutter/material.dart';

import '../legal/legal_screen.dart';

/// 첫 실행 온보딩 (EWOS-41/53). 약관·개인정보 동의 체크리스트 + 시작하기.
/// 로그인 기록이 없을 때(최초 1회) 표시된다. 동의 완료 시 [onStart]를 호출한다.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onStart});

  final Future<void> Function() onStart;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _terms = false;
  bool _privacy = false;
  bool _busy = false;

  bool get _allAgreed => _terms && _privacy;

  Future<void> _start() async {
    setState(() => _busy = true);
    await widget.onStart(); // 부모가 플래그 저장 후 로그인 화면으로 전환한다.
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
                CheckboxListTile(
                  value: _allAgreed,
                  onChanged: _busy
                      ? null
                      : (bool? v) => setState(() {
                            _terms = v ?? false;
                            _privacy = v ?? false;
                          }),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('전체 동의',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const Divider(height: 1),
                _checkRow('이용약관 동의 (필수)', LegalDoc.terms, _terms,
                    (bool v) => setState(() => _terms = v)),
                _checkRow('개인정보처리방침 동의 (필수)', LegalDoc.privacy, _privacy,
                    (bool v) => setState(() => _privacy = v)),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: (_allAgreed && !_busy) ? _start : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A18),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('시작하기',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
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
        const Text('이화 발주에 오신 것을 환영합니다',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        const Text('서비스 이용을 위해 약관에 동의해 주세요.',
            style: TextStyle(fontSize: 13, color: Color(0xFF6B6A64))),
      ],
    );
  }

  Widget _checkRow(
      String label, LegalDoc doc, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: <Widget>[
        Checkbox(
          value: value,
          onChanged: _busy ? null : (bool? v) => onChanged(v ?? false),
        ),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        TextButton(
          onPressed: () => LegalScreen.open(context, doc),
          child: const Text('보기'),
        ),
      ],
    );
  }
}
