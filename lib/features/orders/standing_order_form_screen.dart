import 'package:flutter/material.dart';
import '../../core/models/favorite.dart';
import '../../core/models/partner.dart';
import '../../core/models/standing_order.dart';
import '../../core/services/favorite_service.dart';
import '../../core/services/standing_order_service.dart';

class StandingOrderFormScreen extends StatefulWidget {
  const StandingOrderFormScreen({
    super.key,
    required this.partner,
    this.order,
  });

  final Partner partner;
  final StandingOrder? order;

  @override
  State<StandingOrderFormScreen> createState() => _StandingOrderFormScreenState();
}

class _StandingOrderFormScreenState extends State<StandingOrderFormScreen> {
  Favorite? _selectedFavorite;
  StandingOrderCycleType _cycleType = StandingOrderCycleType.weekly;
  final List<int> _daysOfWeek = [];
  final TextEditingController _intervalCtrl = TextEditingController(text: '7');
  TimeOfDay _preferredTime = const TimeOfDay(hour: 9, minute: 0);
  bool _autoConfirm = false;

  @override
  void initState() {
    super.initState();
    if (widget.order != null) {
      _cycleType = widget.order!.cycle.type;
      _daysOfWeek.addAll(widget.order!.cycle.daysOfWeek);
      _intervalCtrl.text = (widget.order!.cycle.intervalDays ?? 7).toString();
      _preferredTime = widget.order!.preferredTime;
      _autoConfirm = widget.order!.autoConfirm;
      // Note: _selectedFavorite will be loaded from stream if match found or handled manually
    }
  }

  @override
  void dispose() {
    _intervalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.order == null ? '정기발주 등록' : '정기발주 수정'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('1. 발주 템플릿 불러오기'),
            _favoriteSelector(),
            const SizedBox(height: 24),
            _sectionTitle('2. 주기 설정'),
            _cycleTypeSelector(),
            const SizedBox(height: 12),
            if (_cycleType == StandingOrderCycleType.weekly) _weeklySelector(),
            if (_cycleType == StandingOrderCycleType.interval) _intervalInput(),
            const SizedBox(height: 24),
            _sectionTitle('3. 발주 시간'),
            ListTile(
              title: Text('희망 시간: ${_preferredTime.format(context)}'),
              trailing: const Icon(Icons.access_time),
              onTap: _selectTime,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isValid ? _save : null,
                child: const Text('저장하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _favoriteSelector() {
    return StreamBuilder<List<Favorite>>(
      stream: FavoriteService.watch(widget.partner.id),
      builder: (context, snap) {
        final favorites = snap.data ?? [];
        if (favorites.isEmpty) return const Text('등록된 즐겨찾기가 없습니다.');

        // _selectedFavorite이 현재 불러온 favorites 목록에 있는지 확인
        if (_selectedFavorite != null) {
          final bool exists = favorites.any((f) => f.id == _selectedFavorite!.id);
          if (!exists) {
            _selectedFavorite = null;
          } else {
            // 목록에 있는 최신 객체로 교체 (참조 일치 유도)
            _selectedFavorite = favorites.firstWhere((f) => f.id == _selectedFavorite!.id);
          }
        }

        if (_selectedFavorite == null && widget.order != null) {
          try {
            _selectedFavorite = favorites.firstWhere((f) => f.id == widget.order!.favoriteId);
          } catch (_) {}
        }

        return DropdownButtonFormField<Favorite>(
          value: _selectedFavorite,
          items: favorites.map((f) {
            return DropdownMenuItem<Favorite>(
              value: f, 
              child: Text(f.name),
            );
          }).toList(),
          onChanged: (v) => setState(() => _selectedFavorite = v),
          decoration: const InputDecoration(
            border: OutlineInputBorder(), 
            hintText: '사용할 템플릿을 선택하세요',
            isDense: true,
          ),
        );
      },
    );
  }

  Widget _cycleTypeSelector() {
    return SegmentedButton<StandingOrderCycleType>(
      segments: StandingOrderCycleType.values.map((t) {
        return ButtonSegment(value: t, label: Text(t.label));
      }).toList(),
      selected: {_cycleType},
      onSelectionChanged: (v) => setState(() => _cycleType = v.first),
    );
  }

  Widget _weeklySelector() {
    final days = ['월', '화', '수', '목', '금', '토', '일'];
    return Wrap(
      spacing: 8,
      children: List.generate(7, (i) {
        final dayNum = i + 1;
        final isSelected = _daysOfWeek.contains(dayNum);
        return FilterChip(
          label: Text(days[i]),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _daysOfWeek.add(dayNum);
              } else {
                _daysOfWeek.remove(dayNum);
              }
            });
          },
        );
      }),
    );
  }

  Widget _intervalInput() {
    return Row(
      children: [
        const Text('매 '),
        SizedBox(
          width: 60,
          child: TextField(
            controller: _intervalCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(isDense: true),
          ),
        ),
        const Text(' 일 마다'),
      ],
    );
  }

  bool get _isValid {
    if (_selectedFavorite == null) return false;
    if (_cycleType == StandingOrderCycleType.weekly && _daysOfWeek.isEmpty) return false;
    if (_cycleType == StandingOrderCycleType.interval) {
      final int? v = int.tryParse(_intervalCtrl.text);
      if (v == null || v <= 0) return false;
    }
    return true;
  }

  void _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _preferredTime,
      cancelText: '취소',
      confirmText: '확인',
      helpText: '발주 시간 선택',
    );
    if (picked != null && picked != _preferredTime) {
      setState(() => _preferredTime = picked);
    }
  }

  void _save() async {
    final cycle = StandingOrderCycle(
      type: _cycleType,
      daysOfWeek: _daysOfWeek,
      intervalDays: int.tryParse(_intervalCtrl.text),
    );

    final nextDate = StandingOrderService.calculateNextOrderDate(
      cycle,
      DateTime.now(),
    );

    final order = StandingOrder(
      id: widget.order?.id ?? '',
      partnerId: widget.partner.id,
      favoriteId: _selectedFavorite!.id,
      favoriteName: _selectedFavorite!.name,
      cycle: cycle,
      preferredTime: _preferredTime,
      status: widget.order?.status ?? StandingOrderStatus.active,
      autoConfirm: true, // 항상 즉시 발주
      nextOrderDate: nextDate,
      lastOrderDate: widget.order?.lastOrderDate,
    );

    await StandingOrderService.save(order);
    if (mounted) Navigator.pop(context);
  }
}
