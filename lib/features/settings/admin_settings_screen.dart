import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/cafe24_status.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/fcm_service.dart';
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
