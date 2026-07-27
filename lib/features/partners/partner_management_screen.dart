import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/partner.dart';
import '../../core/services/invite_service.dart';

/// 운영자 거래처 관리. 거래처 등록, 초대 코드 발급, 활성/비활성을 담당한다.
/// 삭제는 없다 — 거래 중단은 비활성화로 처리해 데이터를 보존한다.
class PartnerManagementScreen extends StatelessWidget {
  const PartnerManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('partners').orderBy('name');
    return Scaffold(
      appBar: AppBar(
        title: const Text('거래처 관리'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openForm(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (BuildContext context,
            AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<Partner> partners =
              snap.data!.docs.map(Partner.fromDoc).toList();
          if (partners.isEmpty) {
            return const Center(
              child: Text('등록된 거래처가 없습니다. 오른쪽 위 + 로 등록하세요.',
                  style: TextStyle(color: Color(0xFF8A8880))),
            );
          }
          return ListView.separated(
            itemCount: partners.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int i) =>
                _PartnerTile(partner: partners[i]),
          );
        },
      ),
    );
  }

  Future<void> _openForm(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _PartnerForm(),
    );
  }
}

/// 거래처 한 행: 정보 + 활성 토글 + 초대 코드 영역.
class _PartnerTile extends StatefulWidget {
  const _PartnerTile({required this.partner});

  final Partner partner;

  @override
  State<_PartnerTile> createState() => _PartnerTileState();
}

class _PartnerTileState extends State<_PartnerTile> {
  bool _issuing = false;

  Future<void> _toggleActive(bool next) async {
    if (!next) {
      final bool ok = await _confirmDeactivate();
      if (!ok) return;
    }
    await FirebaseFirestore.instance
        .collection('partners')
        .doc(widget.partner.id)
        .update(<String, dynamic>{'active': next});
  }

  Future<bool> _confirmDeactivate() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('${widget.partner.name} 비활성화'),
        content: const Text('비활성화하면 이 거래처는 로그인할 수 없습니다. 계속할까요?'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('비활성화')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _issueCode() async {
    setState(() => _issuing = true);
    try {
      final Invite invite = await InviteService.issue(widget.partner.id);
      if (mounted) _showCode(invite);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('발급 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  void _showCode(Invite invite) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('${widget.partner.name} 초대 코드'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SelectableText(invite.code,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w500, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text('${invite.expiresAt.month}.${invite.expiresAt.day}까지 · 1회용',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: invite.code));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('코드를 복사했습니다')));
            },
            child: const Text('복사'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Partner p = widget.partner;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(p.name,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              if (!p.active)
                const Text('비활성',
                    style: TextStyle(fontSize: 11, color: Color(0xFFA32D2D))),
              const Spacer(),
              Switch(value: p.active, onChanged: _toggleActive),
            ],
          ),
          if (p.manager != null || p.phone != null)
            Text('${p.manager ?? ''} ${p.phone ?? ''}'.trim(),
                style: const TextStyle(fontSize: 12, color: Color(0xFF5F5E5A))),
          if (p.cafe24MemberId != null)
            Text('카페24 ID: ${p.cafe24MemberId}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _issuing ? null : _issueCode,
                icon: _issuing
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.vpn_key_outlined, size: 16),
                label: const Text('초대 코드 발급'),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _openAddresses,
                icon: const Icon(Icons.local_shipping_outlined, size: 16),
                label: Text('배송지 ${p.addresses.length}'),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openAddresses() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => _AddressSheet(
        partnerId: widget.partner.id,
        initial: widget.partner.addresses,
      ),
    );
  }
}

/// 거래처 배송지 관리 시트. partners/{id}.addresses 배열 전체를 갱신한다.
/// 발주 확인 화면의 배송지 드롭다운이 이 데이터를 사용한다.
class _AddressSheet extends StatefulWidget {
  const _AddressSheet({required this.partnerId, required this.initial});

  final String partnerId;
  final List<PartnerAddress> initial;

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<_AddressSheet> {
  late List<PartnerAddress> _addresses = List<PartnerAddress>.of(widget.initial);
  bool _saving = false;

  Future<void> _persist() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('partners')
          .doc(widget.partnerId)
          .update(<String, dynamic>{
        'addresses':
            _addresses.map((PartnerAddress a) => a.toMap()).toList(),
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('배송지 저장에 실패했습니다')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 기본 배송지는 항상 하나만. 지정된 항목만 true로, 없으면 첫 항목을 기본으로.
  List<PartnerAddress> _normalizeDefault(List<PartnerAddress> list, int? keep) {
    final List<PartnerAddress> next = <PartnerAddress>[
      for (int i = 0; i < list.length; i++)
        list[i].copyWith(isDefault: keep == null ? list[i].isDefault : i == keep),
    ];
    if (next.isNotEmpty && !next.any((PartnerAddress a) => a.isDefault)) {
      next[0] = next[0].copyWith(isDefault: true);
    }
    return next;
  }

  Future<void> _addOrEdit({int? index}) async {
    final PartnerAddress? r = await _showAddressDialog(
        initial: index != null ? _addresses[index] : null);
    if (r == null) return;
    setState(() {
      List<PartnerAddress> next = List<PartnerAddress>.of(_addresses);
      if (index != null) {
        next[index] = r;
      } else {
        next.add(r);
      }
      // 방금 항목을 기본으로 지정했다면 그 항목만 기본으로 맞춘다.
      _addresses = _normalizeDefault(next, r.isDefault ? (index ?? next.length - 1) : null);
    });
    await _persist();
  }

  Future<void> _delete(int index) async {
    setState(() {
      final List<PartnerAddress> next = List<PartnerAddress>.of(_addresses)
        ..removeAt(index);
      _addresses = _normalizeDefault(next, null);
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('배송지 관리',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              const Spacer(),
              if (_saving)
                const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),
          if (_addresses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('등록된 배송지가 없습니다.',
                  style: TextStyle(color: Color(0xFF8A8880))),
            )
          else
            ...List<Widget>.generate(_addresses.length, _tile),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _addOrEdit(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('배송지 추가'),
          ),
        ],
      ),
    );
  }

  Widget _tile(int i) {
    final PartnerAddress a = _addresses[i];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Row(
        children: <Widget>[
          Flexible(child: Text(a.label, overflow: TextOverflow.ellipsis)),
          if (a.isDefault)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Text('기본',
                  style: TextStyle(fontSize: 11, color: Color(0xFF3B7A57))),
            ),
        ],
      ),
      subtitle: Text(a.address, style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: _saving ? null : () => _addOrEdit(index: i),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: _saving ? null : () => _delete(i),
          ),
        ],
      ),
    );
  }

  Future<PartnerAddress?> _showAddressDialog({PartnerAddress? initial}) {
    final TextEditingController labelCtrl =
        TextEditingController(text: initial?.label ?? '');
    final TextEditingController addrCtrl =
        TextEditingController(text: initial?.address ?? '');
    bool isDefault = initial?.isDefault ?? false;
    return showDialog<PartnerAddress>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setLocal) => AlertDialog(
          title: Text(initial == null ? '배송지 추가' : '배송지 수정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                    labelText: '이름 (예: 본점)', isDense: true),
              ),
              TextField(
                controller: addrCtrl,
                decoration:
                    const InputDecoration(labelText: '주소', isDense: true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: isDefault,
                title: const Text('기본 배송지', style: TextStyle(fontSize: 14)),
                onChanged: (bool? v) => setLocal(() => isDefault = v ?? false),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소')),
            FilledButton(
              onPressed: () {
                final String label = labelCtrl.text.trim();
                final String addr = addrCtrl.text.trim();
                if (label.isEmpty || addr.isEmpty) return;
                Navigator.pop(
                    context,
                    PartnerAddress(
                        label: label, address: addr, isDefault: isDefault));
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 거래처 등록 폼. 거래처명만 필수, 나머지는 선택.
class _PartnerForm extends StatefulWidget {
  const _PartnerForm();

  @override
  State<_PartnerForm> createState() => _PartnerFormState();
}

class _PartnerFormState extends State<_PartnerForm> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _manager = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _cafe24 = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _manager.dispose();
    _phone.dispose();
    _cafe24.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('partners').add(<String, dynamic>{
        'name': name,
        'manager': _manager.text.trim().isEmpty ? null : _manager.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'cafe24MemberId':
            _cafe24.text.trim().isEmpty ? null : _cafe24.text.trim(),
        'active': true,
        'addresses': <dynamic>[],
      });
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('등록에 실패했습니다')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('거래처 등록',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          _field(_name, '거래처명 *'),
          _field(_manager, '담당자'),
          _field(_phone, '연락처', keyboard: TextInputType.phone),
          _field(_cafe24, '카페24 회원 ID (선택)'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A18),
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('등록'),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        enabled: !_saving,
        decoration: InputDecoration(
            labelText: label, isDense: true, border: const OutlineInputBorder()),
      ),
    );
  }
}
