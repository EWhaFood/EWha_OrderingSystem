import 'dart:math';

import 'package:flutter/material.dart';
import 'package:portone_flutter/v2.dart';

import '../config/payment_config.dart';

/// 결제 결과. ok=true면 결제 성공(서버 검증은 createPaidOrder에서 별도 수행).
class PaymentResult {
  const PaymentResult(this.ok, {this.message});

  final bool ok;
  final String? message;
}

/// PortOne V2 간편결제 (EWOS-52). 결제창을 띄우고 결과만 돌려준다.
/// 금액 확정·주문 생성은 서버(createPaidOrder)가 결제를 검증한 뒤 처리한다.
class PaymentService {
  PaymentService._();

  /// paymentId는 앱에서 발급하고 서버가 이 값으로 PortOne에 결제를 조회·검증한다.
  static String newPaymentId() {
    final String rand = Random().nextInt(0x7fffffff).toRadixString(16);
    return 'ewos_${DateTime.now().millisecondsSinceEpoch}_$rand';
  }

  /// 결제창을 띄운다. 성공(code==null)이면 ok=true.
  static Future<PaymentResult> requestPayment(
    BuildContext context, {
    required String paymentId,
    required String orderName,
    required int amount,
  }) async {
    final PaymentResponse? res =
        await Navigator.of(context).push<PaymentResponse>(
      MaterialPageRoute<PaymentResponse>(
        builder: (BuildContext ctx) => PortonePayment(
          appBar: AppBar(title: const Text('결제')),
          data: PaymentRequest(
            storeId: PaymentConfig.storeId,
            channelKey: PaymentConfig.channelKey,
            paymentId: paymentId,
            orderName: orderName,
            totalAmount: amount,
            currency: Currency.KRW,
            payMethod: PaymentPayMethod.CARD,
            appScheme: PaymentConfig.appScheme,
          ),
          callback: (PaymentResponse response) =>
              Navigator.of(ctx).pop(response),
        ),
      ),
    );
    if (res == null) return const PaymentResult(false, message: '결제가 취소되었습니다.');
    if (res.code != null) {
      return PaymentResult(false, message: res.message ?? '결제에 실패했습니다.');
    }
    return const PaymentResult(true);
  }
}
