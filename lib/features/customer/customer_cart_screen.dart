import 'package:flutter/material.dart';

import '../../core/config/payment_config.dart';
import '../../core/models/product.dart';
import '../../core/services/order_service.dart';
import '../../core/services/payment_service.dart';
import '../../core/utils/format.dart';
import '../orders/cart.dart';

/// 일반 사용자(B2C) 장바구니·주문 화면 (EWOS-53).
/// 담은 상품 확인 → 배송지 입력 → 간편결제 → 서버 검증 후 주문 생성.
class CustomerCartScreen extends StatefulWidget {
  const CustomerCartScreen({
    super.key,
    required this.uid,
    required this.products,
  });

  final String uid;
  final List<Product> products;

  @override
  State<CustomerCartScreen> createState() => _CustomerCartScreenState();
}

class _CustomerCartScreenState extends State<CustomerCartScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _addrCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  List<Product> get _lines =>
      widget.products.where((Product p) => Cart.qtyOf(p.id) > 0).toList();

  int get _total =>
      _lines.fold(0, (int s, Product p) => s + p.price * Cart.qtyOf(p.id));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('장바구니')),
      body: ValueListenableBuilder<Map<String, int>>(
        valueListenable: Cart.items,
        builder: (BuildContext context, Map<String, int> _, _) {
          if (_lines.isEmpty) {
            return const Center(child: Text('장바구니가 비었습니다.'));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: <Widget>[
              ..._lines.map(_itemTile),
              _totalRow(),
              const Divider(height: 24),
              _deliveryForm(),
            ],
          );
        },
      ),
      bottomNavigationBar: _checkoutBar(),
    );
  }

  Widget _itemTile(Product p) {
    final int qty = Cart.qtyOf(p.id);
    return ListTile(
      title: Text(p.name, style: const TextStyle(fontSize: 14)),
      subtitle: Text('${formatWon(p.price)} × $qty'),
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
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _deliveryForm() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('배송 정보',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _field(_nameCtrl, '받는 분', TextInputType.name),
          const SizedBox(height: 10),
          _field(_phoneCtrl, '연락처', TextInputType.phone),
          const SizedBox(height: 10),
          _field(_addrCtrl, '배송지 주소', TextInputType.streetAddress),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, TextInputType type) {
    return TextField(
      controller: c,
      keyboardType: type,
      enabled: !_submitting,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _checkoutBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed:
              (_submitting || _lines.isEmpty) ? null : _chooseMethodAndPay,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF185FA5),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text('${formatWon(_total)} 결제하고 주문',
                  style: const TextStyle(fontSize: 15)),
        ),
      ),
    );
  }

  /// 배송지 검증 → 결제 수단 선택 → 결제 → 주문 생성.
  Future<void> _chooseMethodAndPay() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty ||
        _addrCtrl.text.trim().isEmpty) {
      _toast('받는 분·연락처·배송지 주소를 모두 입력해 주세요.');
      return;
    }
    if (!PaymentConfig.isConfigured) {
      _toast('간편결제 설정(PortOne 키)이 아직 없습니다.');
      return;
    }
    final PaymentMethod? method = await showModalBottomSheet<PaymentMethod>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('결제 수단 선택',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            for (final PaymentMethod m in PaymentMethod.values)
              ListTile(
                leading: Icon(m.icon),
                title: Text(m.label),
                onTap: () => Navigator.pop(ctx, m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (method != null) await _payWith(method);
  }

  Future<void> _payWith(PaymentMethod method) async {
    setState(() => _submitting = true);
    final int amount = _total;
    final String paymentId = PaymentService.newPaymentId();
    final String orderName = _lines.length == 1
        ? _lines.first.name
        : '${_lines.first.name} 외 ${_lines.length - 1}건';
    try {
      final PaymentResult result = await PaymentService.requestPayment(
        context,
        paymentId: paymentId,
        orderName: orderName,
        amount: amount,
        method: method,
      );
      if (!result.ok) {
        _toast(result.message ?? '결제가 취소되었습니다.');
        if (mounted) setState(() => _submitting = false);
        return;
      }
      final String orderNo = await OrderService.createPaidOrder(
        paymentId: paymentId,
        qtys: Map<String, int>.from(Cart.items.value),
        shippingAddress: _addrCtrl.text.trim(),
        customerName: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );
      Cart.clear();
      if (mounted) await _showDone(orderNo, amount);
    } catch (_) {
      _toast('결제는 되었으나 주문 처리에 실패했습니다. 고객센터에 문의해 주세요.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showDone(String orderNo, int amount) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('주문이 완료되었습니다'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('주문번호 $orderNo',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
            const SizedBox(height: 12),
            Text('결제 금액  ${formatWon(amount)}',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context); // 장바구니 닫고 홈으로
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
