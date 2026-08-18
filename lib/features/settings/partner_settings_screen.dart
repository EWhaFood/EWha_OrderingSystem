import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/models/partner.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/fcm_service.dart';
import '../../core/services/order_service.dart';
import '../../core/utils/format.dart';
import '../legal/legal_screen.dart';
import '../partners/address_sheet.dart';

/// 거래처 본인 설정. 배송지 관리·알림 수신·비밀번호 변경·로그아웃.
/// 배송지는 규칙상 자기 partners 문서의 addresses만 수정 가능하다.
class PartnerSettingsScreen extends StatefulWidget {
  const PartnerSettingsScreen(
      {super.key, required this.uid, required this.partner});

  final String uid; // 사용자 고유 ID
  final Partner partner; // 거래처 정보 객체

  @override
  State<PartnerSettingsScreen> createState() => _PartnerSettingsScreenState();
}

class _PartnerSettingsScreenState extends State<PartnerSettingsScreen> {
  bool? _notify; // 알림 활성화 여부 (null이면 로딩 중)

  @override
  void initState() {
    super.initState();
    // FCM 서비스로부터 현재 기기의 알림 설정 상태를 가져옴
    FcmService.isEnabled(widget.uid).then((bool v) {
      if (mounted) setState(() => _notify = v);
    });
  }

  // 알림 설정을 끄거나 켜는 함수
  Future<void> _toggleNotify(bool next) async {
    setState(() => _notify = next);
    await FcmService.setEnabled(widget.uid, next);
  }

  // 배송지 관리 시트를 바텀 시트로 엶
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

  // 화면 하단에 짧은 메시지(스낵바)를 보여줌
  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('내 정보')), // 명세서에 따라 '설정'에서 '내 정보'로 변경
      body: ListView(
        children: <Widget>[
          _InfoCard(partner: widget.partner), // [신규] 상단 거래처 정보 카드 추가
          _CreditCard(partner: widget.partner),
          const Divider(height: 1),
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
            leading: const Icon(Icons.description_outlined),
            title: const Text('이용약관'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => LegalScreen.open(context, LegalDoc.terms),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('개인정보처리방침'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => LegalScreen.open(context, LegalDoc.privacy),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('로그아웃'),
            onTap: () => logout(widget.uid),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.no_accounts_outlined,
                color: Color(0xFFA32D2D)),
            title: const Text('계정 삭제',
                style: TextStyle(color: Color(0xFFA32D2D))),
            subtitle: const Text('계정과 개인정보가 삭제되며 되돌릴 수 없습니다'),
            onTap: _deleteAccount,
          ),
        ],
      ),
    );
  }

  /// 계정 삭제(탈퇴). 재인증(비밀번호)으로 본인을 확인한 뒤 서버에서 삭제한다.
  Future<void> _deleteAccount() async {
    final String? password = await _confirmDelete();
    if (password == null) return;
    final User? user = FirebaseAuth.instance.currentUser;
    final String? email = user?.email;
    if (user == null || email == null) return;
    // 1) 재인증: 실패하면 삭제를 진행하지 않는다.
    try {
      final AuthCredential cred =
          EmailAuthProvider.credential(email: email, password: password);
      await user.reauthenticateWithCredential(cred);
    } on FirebaseAuthException catch (e) {
      _toast(e.code == 'wrong-password' || e.code == 'invalid-credential'
          ? '비밀번호가 올바르지 않습니다'
          : '재인증에 실패했습니다 (${e.code})');
      return;
    }
    // 2) 서버 삭제. 부분 실패 시 좀비 세션을 남기지 않도록 로그아웃한다.
    try {
      await deleteAccount(widget.uid); // 로그아웃되면 인증 리스너가 로그인 화면으로 전환
    } catch (e) {
      _toast('계정 삭제에 실패했습니다. 다시 로그인 후 시도해 주세요.');
      await logout(widget.uid);
    }
  }

  /// 삭제 경고 + 비밀번호 확인 다이얼로그. 확인 시 입력한 비밀번호를 반환한다.
  Future<String?> _confirmDelete() async {
    final TextEditingController pwCtrl = TextEditingController();
    try {
      return await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('계정 삭제'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('계정과 개인정보(이메일·알림 설정)가 삭제됩니다.\n'
                '이 작업은 되돌릴 수 없습니다.\n'
                '확인을 위해 비밀번호를 입력해 주세요.'),
            const SizedBox(height: 12),
            TextField(
              controller: pwCtrl,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: '비밀번호', isDense: true),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFA32D2D)),
            onPressed: () => Navigator.pop(context, pwCtrl.text),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    } finally {
      pwCtrl.dispose();
    }
  }

  // 비밀번호 변경 프로세스 (재인증 후 새 비밀번호 설정)
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

  Future<_PwInput?> _promptPassword() async {
    final TextEditingController curCtrl = TextEditingController();
    final TextEditingController newCtrl = TextEditingController();
    String? err;
    try {
      return await showDialog<_PwInput>(
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
    } finally {
      curCtrl.dispose();
      newCtrl.dispose();
    }
  }
}

/// 비밀번호 변경 입력값.
class _PwInput {
  const _PwInput({required this.current, required this.next});

  final String current;
  final String next;
}

/// 거래처 미수금·외상 한도 카드(읽기 전용). (EWOS-44)
class _CreditCard extends StatelessWidget {
  const _CreditCard({required this.partner});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: OrderService.outstandingFor(partner.id),
      builder: (BuildContext context, AsyncSnapshot<int> snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final int outstanding = snap.data!;
        final bool over =
            partner.hasCreditLimit && outstanding > partner.creditLimit;
        final String limit =
            partner.hasCreditLimit ? formatWon(partner.creditLimit) : '무제한';
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: over ? const Color(0xFFFCF0EF) : const Color(0xFFF5F4EF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.account_balance_wallet_outlined,
                  size: 20,
                  color: over
                      ? const Color(0xFFA32D2D)
                      : const Color(0xFF3B7A57)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('미수금 ${formatWon(outstanding)}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    Text('외상 한도 $limit${over ? '  ⚠ 초과' : ''}',
                        style: TextStyle(
                            fontSize: 12,
                            color: over
                                ? const Color(0xFFA32D2D)
                                : const Color(0xFF8A8880))),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 거래처 정보 카드 (읽기 전용).
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.partner});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F4EF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.business, size: 20, color: Color(0xFF3B7A57)),
              const SizedBox(width: 8),
              Text(
                partner.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1C1B1F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _item(Icons.person_outline, '담당자', partner.manager ?? '-'),
          const SizedBox(height: 8),
          _item(Icons.phone_outlined, '연락처', partner.phone ?? '-'),
          const SizedBox(height: 12),
          const Text(
            '※ 정보 수정은 운영자에게 요청해 주세요.',
            style: TextStyle(fontSize: 12, color: Color(0xFF8A8880)),
          ),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String label, String value) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: const Color(0xFF8A8880)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 14, color: Color(0xFF8A8880)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF1C1B1F),
          ),
        ),
      ],
    );
  }
}
