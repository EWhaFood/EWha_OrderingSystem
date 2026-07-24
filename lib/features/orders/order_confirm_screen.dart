import 'package:flutter/material.dart';

import '../../core/models/partner.dart';
import '../../core/models/product.dart';
import '../../core/services/order_service.dart';
import '../../core/utils/format.dart';
import 'cart.dart';

/// 발주 확인 화면. 담은 품목을 최종 점검하고 배송지·메모를 붙여 제출한다.
/// 가격은 이 화면 진입 시 읽은 값을 보여주고, 실제 저장 단가는 제출 시점에 다시 스냅샷한다.
class OrderConfirmScreen extends StatefulWidget {
  const OrderConfirmScreen({
    super.key,
    required this.uid,
    required this.partner,
    required this.products,
  });

  final String uid;
  final Partner partner;

  /// 담긴 품목의 상품 정보 (발주 등록 화면에서 이미 읽은 것을 넘겨받는다).
  final List<Product> products;

  @override
  State<OrderConfirmScreen> createState() => _OrderConfirmScreenState();
}

class _OrderConfirmScreenState extends State<OrderConfirmScreen> {
  final TextEditingController _memoCtrl = TextEditingController();
  PartnerAddress? _address;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _address = widget.partner.defaultAddress;
  }

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  List<Product> get _lines => widget.products
      .where((Product p) => Cart.qtyOf(p.id) > 0)
      .toList();

  int get _total => _lines.fold(
      0, (int sum, Product p) => sum + p.price * Cart.qtyOf(p.id));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('발주 확인')),
      body: ValueListenableBuilder<Map<String, int>>(
        valueListenable: Cart.items,
        builder: (BuildContext context, Map<String, int> _, _) {
          if (_lines.isEmpty) {
            return const Center(child: Text('담긴 품목이 없습니다'));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: <Widget>[
              ..._lines.map(_itemTile),
              _totalRow(),
              _addressSection(),
              _memoSection(),
            ],
          );
        },
      ),
      bottomNavigationBar: _submitBar(),
    );
  }

  Widget _itemTile(Product p) {
    final int qty = Cart.qtyOf(p.id);
    return ListTile(
      title: Text(p.name, style: const TextStyle(fontSize: 14)),
      subtitle: Text('${formatWon(p.price)} × $qty',
          style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: _submitting ? null : () => Cart.add(p.id, -1),
          ),
          Text('$qty', style: const TextStyle(fontSize: 15)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _submitting ? null : () => Cart.add(p.id, 1),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _submitting ? null : () => Cart.remove(p.id),
          ),
        ],
      ),
    );
  }

  Widget _totalRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: <Widget>[
          const Text('합계',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(formatWon(_total),
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _addressSection() {
    final List<PartnerAddress> addresses = widget.partner.addresses;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('배송지', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          if (addresses.isEmpty)
            const Text('등록된 배송지가 없습니다. 관리자에게 문의하세요.',
                style: TextStyle(fontSize: 13, color: Color(0xFF8A8880)))
          else
            DropdownButton<PartnerAddress>(
              isExpanded: true,
              value: _address,
              items: addresses
                  .map((PartnerAddress a) => DropdownMenuItem<PartnerAddress>(
                        value: a,
                        child: Text('${a.label} · ${a.address}',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (PartnerAddress? v) => setState(() => _address = v),
            ),
        ],
      ),
    );
  }

  Widget _memoSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _memoCtrl,
        enabled: !_submitting,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: '요청 메모 (선택)',
          hintText: '예) 금요일까지 부탁드립니다',
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _submitBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: (_submitting || _lines.isEmpty) ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1A1A18),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text('${formatWon(_total)} 발주 제출',
                  style: const TextStyle(fontSize: 15)),
        ),
      ),
    );
  }

  /// 제출. 중복 제출은 _submitting 잠금으로 막고, 실패 시 사유를 안내한다.
  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final String orderNo = await OrderService.submit(
        uid: widget.uid,
        partnerId: widget.partner.id,
        partnerName: widget.partner.name,
        qtys: Map<String, int>.from(Cart.items.value),
        shippingAddress: _address?.address,
        memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
      );
      Cart.clear();
      if (mounted) await _showDone(orderNo);
    } on OrderSubmitException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('발주 제출에 실패했습니다. 네트워크 상태를 확인하고 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showDone(String orderNo) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('발주가 접수되었습니다'),
        content: Text('발주번호 $orderNo\n처리 상황은 알림으로 안내드립니다.'),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }
}
