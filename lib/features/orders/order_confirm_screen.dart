import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config/payment_config.dart';
import '../../core/models/partner.dart';
import '../../core/models/product.dart';
import '../../core/services/order_service.dart';
import '../../core/services/payment_service.dart';
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
  DateTime? _desiredDate;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _address = widget.partner.defaultAddress;
    _initDesiredDate();
  }

  Future<void> _initDesiredDate() async {
    final TimeOfDay cutoff = await OrderService.getCutoffTime();
    final DateTime processDate =
        OrderService.calculateProcessDate(DateTime.now(), cutoff);
    setState(() => _desiredDate = processDate);
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
              _desiredDateSection(),
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

  Widget _desiredDateSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: InkWell(
        onTap: _submitting ? null : _selectDesiredDate,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E4DE)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.calendar_today_outlined,
                  size: 18, color: Color(0xFF5F5E5A)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('희망 배송일',
                        style: TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
                    Text(
                      _desiredDate == null
                          ? '날짜를 선택하세요'
                          : '${_desiredDate!.year}.${_desiredDate!.month}.${_desiredDate!.day} '
                              '(${_weekday(_desiredDate!)})',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF8A8880)),
            ],
          ),
        ),
      ),
    );
  }

  String _weekday(DateTime d) {
    const List<String> days = <String>['월', '화', '수', '목', '금', '토', '일'];
    return days[d.weekday - 1];
  }

  Future<void> _selectDesiredDate() async {
    final TimeOfDay cutoff = await OrderService.getCutoffTime();
    final DateTime minDate =
        OrderService.calculateProcessDate(DateTime.now(), cutoff);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _desiredDate ?? minDate,
      firstDate: minDate,
      lastDate: minDate.add(const Duration(days: 30)),
      selectableDayPredicate: (DateTime day) {
        // 주말(토, 일)은 선택 불가 (OrderService.calculateProcessDate 규칙과 일치)
        return day.weekday != DateTime.saturday &&
            day.weekday != DateTime.sunday;
      },
    );
    if (picked != null && picked != _desiredDate) {
      setState(() => _desiredDate = picked);
    }
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
    final bool busy = _submitting || _lines.isEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : _chooseMethodAndPay,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF185FA5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('${formatWon(_total)} 간편결제로 발주',
                    style: const TextStyle(fontSize: 15)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : _submit,
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
                    : const Text('계좌이체로 발주',
                        style: TextStyle(fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 결제 수단(카드/카카오페이/네이버페이)을 고르고 결제를 시작한다 (EWOS-52/54).
  Future<void> _chooseMethodAndPay() async {
    if (_lines.isEmpty) return;
    if (!PaymentConfig.isConfigured) {
      _showError('간편결제 설정(PortOne 키)이 아직 없습니다. 계좌이체로 발주해 주세요.');
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

  /// 선택한 수단으로 결제 → 성공 시 서버가 검증 후 주문 생성 (EWOS-52/54).
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
        _showError(result.message ?? '결제가 취소되었습니다.');
        if (mounted) setState(() => _submitting = false);
        return;
      }
      final String orderNo = await OrderService.createPaidOrder(
        paymentId: paymentId,
        qtys: Map<String, int>.from(Cart.items.value),
        shippingAddress: _address?.address,
        memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
        desiredDeliveryDate: _desiredDate,
      );
      Cart.clear();
      if (mounted) await _showPaidDone(orderNo, amount);
    } catch (_) {
      _showError('결제는 되었으나 발주 처리에 실패했습니다. 운영자에게 문의해 주세요.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 간편결제 완료 안내(결제 끝났으므로 계좌 안내 없음).
  Future<void> _showPaidDone(String orderNo, int amount) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('결제가 완료되었습니다'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('발주번호 $orderNo',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
            const SizedBox(height: 12),
            Text('결제 금액  ${formatWon(amount)}',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('발주가 접수되었습니다.', style: TextStyle(fontSize: 13)),
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
    if (mounted) Navigator.pop(context);
  }

  /// 제출. 중복 제출은 _submitting 잠금으로 막고, 실패 시 사유를 안내한다.
  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      // 외상 한도 경고(EWOS-44): 미수금+이번 발주액이 한도 초과면 확인받는다(차단 아님).
      if (widget.partner.hasCreditLimit) {
        final int outstanding =
            await OrderService.outstandingFor(widget.partner.id);
        if (outstanding + _total > widget.partner.creditLimit &&
            !await _confirmOverLimit(outstanding)) {
          if (mounted) setState(() => _submitting = false);
          return;
        }
      }
      final String orderNo = await OrderService.submit(
        uid: widget.uid,
        partnerId: widget.partner.id,
        partnerName: widget.partner.name,
        qtys: Map<String, int>.from(Cart.items.value),
        shippingAddress: _address?.address,
        memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
        desiredDeliveryDate: _desiredDate,
      );
      final int amount = _total; // Cart 비우기 전에 결제 금액을 캡처
      Cart.clear();
      if (mounted) await _showDone(orderNo, amount);
    } on OrderSubmitException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('발주 제출에 실패했습니다. 네트워크 상태를 확인하고 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 외상 한도 초과 확인 다이얼로그. 계속하면 true. (EWOS-44, 경고만·차단 아님)
  Future<bool> _confirmOverLimit(int outstanding) async {
    final int after = outstanding + _total;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('외상 한도 초과'),
        content: Text('현재 미수금 ${formatWon(outstanding)}에 이번 발주 '
            '${formatWon(_total)}를 더하면 ${formatWon(after)}로 '
            '한도 ${formatWon(widget.partner.creditLimit)}를 넘습니다.\n'
            '그래도 발주할까요?'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('계속 발주')),
        ],
      ),
    );
    return ok ?? false;
  }

  /// 발주 완료 안내. 계좌이체 즉시결제라 결제 금액과 입금 계좌를 함께 안내한다. (EWOS-44)
  Future<void> _showDone(String orderNo, int amount) async {
    final ({String bank, String number, String holder}) acct =
        await OrderService.getDepositAccount();
    if (!mounted) return;
    final bool hasAcct = acct.number.isNotEmpty;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('발주가 접수되었습니다'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('발주번호 $orderNo',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
            const SizedBox(height: 12),
            Text('결제 금액  ${formatWon(amount)}',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (hasAcct) ...<Widget>[
              const Text('아래 계좌로 입금해 주세요.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              Text('${acct.bank} ${acct.number}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF3B7A57))),
              Text('예금주 ${acct.holder}',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
            ] else
              const Text('입금 계좌는 운영자에게 문의해 주세요.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF8A8880))),
            const SizedBox(height: 8),
            const Text('입금이 확인되면 발주가 처리됩니다.',
                style: TextStyle(fontSize: 12, color: Color(0xFF8A8880))),
          ],
        ),
        actions: <Widget>[
          if (hasAcct)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: acct.number));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('계좌번호를 복사했습니다')));
              },
              child: const Text('계좌 복사'),
            ),
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
