import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/cafe24_status.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/fcm_service.dart';
import '../../core/services/maintenance_service.dart';
import '../../core/services/order_service.dart';
import '../legal/legal_screen.dart';

/// 운영자 설정 화면. 카페24 연동 상태, 알림 설정, 로그아웃을 담당한다.
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key, required this.uid});

  final String uid;

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  bool? _notify; // null이면 조회 중.
  TimeOfDay? _cutoff; // 로컬 상태로 관리하여 즉시 반영

  @override
  void initState() {
    super.initState();
    FcmService.isEnabled(widget.uid).then((bool v) {
      if (mounted) setState(() => _notify = v);
    });
    // 초기 마감 시간 로드
    OrderService.getCutoffTime().then((TimeOfDay v) {
      if (mounted) setState(() => _cutoff = v);
    });
  }

  Future<void> _toggleNotify(bool next) async {
    setState(() => _notify = next);
    await FcmService.setEnabled(widget.uid, next);
  }

  Future<void> _pickCutoffTime() async {
    final TimeOfDay current = _cutoff ?? const TimeOfDay(hour: 15, minute: 0);
    if (!mounted) return;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: '발주 마감 시간 설정',
      cancelText: '취소',
      confirmText: '설정',
      hourLabelText: '시',
      minuteLabelText: '분',
    );

    if (picked != null && mounted) {
      final TimeOfDay oldTime = _cutoff ?? const TimeOfDay(hour: 15, minute: 0);
      setState(() => _cutoff = picked);

      final String timeStr =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      
      try {
        await FirebaseFirestore.instance
            .collection('settings')
            .doc('global')
            .set(<String, dynamic>{'cutoffTime': timeStr}, SetOptions(merge: true));
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('마감 시간이 저장되었습니다.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('저장 실패: $e')),
          );
          // 실패 시 원래대로 복구
          setState(() => _cutoff = oldTime);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: <Widget>[
          const _SectionHeader(title: '카페24 연동 상태'),
          const _Cafe24StatusSection(),
          const Divider(height: 32),
          const _SectionHeader(title: '발주 설정'),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('발주 마감 시간'),
            subtitle: const Text('마감 시간 이후 주문은 익일 처리분으로 분류됩니다'),
            trailing: Text(
              _cutoff != null
                  ? '${_cutoff!.hour.toString().padLeft(2, '0')}:${_cutoff!.minute.toString().padLeft(2, '0')}'
                  : '--:--',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            onTap: _pickCutoffTime,
          ),
          const Divider(height: 32),
          const _SectionHeader(title: '환경 설정'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('신규 발주 알림'),
            subtitle: const Text('새로운 주문이 들어오면 알림을 받습니다'),
            value: _notify ?? false,
            onChanged: _notify == null ? null : _toggleNotify,
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
          const Divider(height: 32),
          const _SectionHeader(title: '테스트 도구'),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined,
                color: Color(0xFFA32D2D)),
            title: const Text('테스트 데이터 삭제',
                style: TextStyle(color: Color(0xFFA32D2D))),
            subtitle: const Text('발주·즐겨찾기·수동상품 등 테스트 데이터를 지웁니다'),
            onTap: _clearTestData,
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

  /// 테스트 데이터 삭제. 확인 다이얼로그에서 범위를 고른 뒤 서버 함수를 호출한다.
  Future<void> _clearTestData() async {
    final _ClearOpts? opts = await _confirmClear();
    if (opts == null) return;
    try {
      final Map<String, int> r = await MaintenanceService.clearTestData(
        partners: opts.partners,
        partnerUsers: opts.partnerUsers,
        cafe24Products: opts.cafe24Products,
      );
      final int total = r.values.fold<int>(0, (int a, int b) => a + b);
      _toast('삭제 완료: 총 $total건 (${r.entries.map((MapEntry<String, int> e) => '${e.key} ${e.value}').join(', ')})');
    } on FirebaseFunctionsException catch (e) {
      _toast(e.code == 'failed-precondition'
          ? '테스트 모드에서만 사용할 수 있습니다 (settings/testMode.enabled=true)'
          : e.code == 'permission-denied'
              ? '운영자만 사용할 수 있습니다'
              : '삭제 실패: ${e.message ?? e.code}');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 삭제 범위 선택 + 경고 다이얼로그. 확인 시 옵션을 반환한다.
  Future<_ClearOpts?> _confirmClear() {
    bool partners = false;
    bool partnerUsers = false;
    bool cafe24Products = false;
    return showDialog<_ClearOpts>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setLocal) => AlertDialog(
          title: const Text('테스트 데이터 삭제'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('발주·즐겨찾기·정기발주·수동 등록 상품이 삭제됩니다.\n'
                  '되돌릴 수 없습니다. 추가로 지울 항목을 선택하세요.'),
              const SizedBox(height: 8),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('거래처(partners)도 삭제'),
                value: partners,
                onChanged: (bool? v) => setLocal(() => partners = v ?? false),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('거래처 계정(users)도 삭제 · 운영자 보존'),
                value: partnerUsers,
                onChanged: (bool? v) =>
                    setLocal(() => partnerUsers = v ?? false),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('카페24 동기화 상품도 삭제'),
                value: cafe24Products,
                onChanged: (bool? v) =>
                    setLocal(() => cafe24Products = v ?? false),
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
              onPressed: () => Navigator.pop(
                  context,
                  _ClearOpts(
                      partners: partners,
                      partnerUsers: partnerUsers,
                      cafe24Products: cafe24Products)),
              child: const Text('삭제'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 테스트 데이터 삭제 옵션.
class _ClearOpts {
  const _ClearOpts({
    required this.partners,
    required this.partnerUsers,
    required this.cafe24Products,
  });

  final bool partners;
  final bool partnerUsers;
  final bool cafe24Products;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// 카페24 연동 상태 섹션. cafe24Status 컬렉션을 실시간 구독한다.
class _Cafe24StatusSection extends StatelessWidget {
  const _Cafe24StatusSection();

  @override
  Widget build(BuildContext context) {
    final Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collection('cafe24Status');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (BuildContext context,
          AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final List<Cafe24Status> list =
            snap.data!.docs.map(Cafe24Status.fromDoc).toList();
        if (list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('연동된 카페24 몰이 없습니다.',
                style: TextStyle(fontSize: 13, color: Color(0xFF8A8880))),
          );
        }
        return Column(
          children: list.map((Cafe24Status s) => _StatusCard(status: s)).toList(),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final Cafe24Status status;

  @override
  Widget build(BuildContext context) {
    final bool warn = !status.connected || status.tokenExpired;
    final DateFormat df = DateFormat('MM/dd HH:mm');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: warn ? const Color(0xFFFCF0EF) : const Color(0xFFF5F4EF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                warn ? Icons.error_outline : Icons.check_circle_outline,
                size: 20,
                color: warn ? const Color(0xFFA32D2D) : const Color(0xFF3B7A57),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status.mallId,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                warn ? (status.tokenExpired ? '토큰 만료' : '연동 끊김') : '연동 정상',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: warn ? const Color(0xFFA32D2D) : const Color(0xFF3B7A57),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _infoRow('Access Token 만료', status.accessExpiresAt != null ? df.format(status.accessExpiresAt!.toDate()) : '-'),
          _infoRow('주문 웹훅 수신 시각', status.lastOrderSync != null ? df.format(status.lastOrderSync!.toDate()) : '-'),
          if (status.productCount != null)
            _infoRow('동기화 상품 수', '${status.productCount}개'),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF5F5E5A))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
