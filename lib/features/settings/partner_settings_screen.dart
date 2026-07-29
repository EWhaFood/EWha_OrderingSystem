import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/models/partner.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/fcm_service.dart';
import '../partners/address_sheet.dart';

/// 거래처 본인 설정. 배송지 관리·알림 수신·비밀번호 변경·로그아웃.
/// 배송지는 규칙상 자기 partners 문서의 addresses만 수정 가능하다.
class PartnerSettingsScreen extends StatefulWidget {
  const PartnerSettingsScreen(
      {super.key, required this.uid, required this.partner});

  final String uid;
  final Partner partner;

  @override
  State<PartnerSettingsScreen> createState() => _PartnerSettingsScreenState();
}

class _PartnerSettingsScreenState extends State<PartnerSettingsScreen> {
  bool? _notify; // null이면 조회 중.

  @override
  void initState() {
    super.initState();
    FcmService.isEnabled(widget.uid).then((bool v) {
      if (mounted) setState(() => _notify = v);
    });
  }

  Future<void> _toggleNotify(bool next) async {
    setState(() => _notify = next);
    await FcmService.setEnabled(widget.uid, next);
  }

  void _openAddresses() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => AddressSheet(
        partnerId: widget.partner.id,
        initial: widget.partner.addresses,
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: const Text('배송지 관리'),
            subtitle: Text('${widget.partner.addresses.length}개 등록됨'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openAddresses,
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('알림 받기'),
            subtitle: const Text('이 기기에서 발주 상태 알림을 받습니다'),
            value: _notify ?? false,
            onChanged: _notify == null ? null : _toggleNotify,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('비밀번호 변경'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _changePassword,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('로그아웃'),
            onTap: () => logout(widget.uid),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword() async {
    final _PwInput? input = await _promptPassword();
    if (input == null) return;
    final User? user = FirebaseAuth.instance.currentUser;
    final String? email = user?.email;
    if (user == null || email == null) return;
    try {
      // updatePassword는 최근 로그인을 요구하므로 현재 비밀번호로 재인증한다.
      final AuthCredential cred =
          EmailAuthProvider.credential(email: email, password: input.current);
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(input.next);
      _toast('비밀번호를 변경했습니다');
    } on FirebaseAuthException catch (e) {
      _toast(_pwError(e.code));
    }
  }

  String _pwError(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return '현재 비밀번호가 올바르지 않습니다';
      case 'weak-password':
        return '새 비밀번호는 6자 이상이어야 합니다';
      default:
        return '변경에 실패했습니다 ($code)';
    }
  }

  Future<_PwInput?> _promptPassword() {
    final TextEditingController curCtrl = TextEditingController();
    final TextEditingController newCtrl = TextEditingController();
    String? err;
    return showDialog<_PwInput>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setLocal) => AlertDialog(
          title: const Text('비밀번호 변경'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: curCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: '현재 비밀번호', isDense: true),
              ),
              TextField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: '새 비밀번호 (6자 이상)', isDense: true),
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(err!,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFA32D2D))),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소')),
            FilledButton(
              onPressed: () {
                if (newCtrl.text.length < 6) {
                  setLocal(() => err = '새 비밀번호는 6자 이상이어야 합니다');
                  return;
                }
                Navigator.pop(context,
                    _PwInput(current: curCtrl.text, next: newCtrl.text));
              },
              child: const Text('변경'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 비밀번호 변경 입력값.
class _PwInput {
  const _PwInput({required this.current, required this.next});

  final String current;
  final String next;
}
