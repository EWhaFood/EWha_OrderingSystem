import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/models/partner.dart';

/// 거래처 배송지 관리 시트. partners/{id}.addresses 배열 전체를 갱신한다.
/// 운영자(거래처 관리)와 거래처 본인(설정)이 함께 쓴다 — 쓰기 권한은 규칙이 판별한다.
/// 발주 확인 화면의 배송지 드롭다운이 이 데이터를 사용한다.
class AddressSheet extends StatefulWidget {
  const AddressSheet({super.key, required this.partnerId, required this.initial});

  final String partnerId;
  final List<PartnerAddress> initial;

  @override
  State<AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<AddressSheet> {
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

  /// 기본 배송지는 항상 하나만. keep이 주어지면 그 항목만 true로,
  /// 없으면 기존 기본 유지하되 하나도 없으면 첫 항목을 기본으로.
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
      final List<PartnerAddress> next = List<PartnerAddress>.of(_addresses);
      if (index != null) {
        next[index] = r;
      } else {
        next.add(r);
      }
      // 방금 항목을 기본으로 지정했다면 그 항목만 기본으로 맞춘다.
      _addresses = _normalizeDefault(
          next, r.isDefault ? (index ?? next.length - 1) : null);
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
