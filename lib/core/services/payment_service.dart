import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/payment_config.dart';

/// 결제 결과. ok=true면 결제 성공(서버 검증은 createPaidOrder에서 별도 수행).
class PaymentResult {
  const PaymentResult(this.ok, {this.message});

  final bool ok;
  final String? message;
}

/// PortOne V2 간편결제 (EWOS-52). 브라우저 SDK를 웹뷰로 로드해 결제창을 띄운다.
/// 금액 확정·주문 생성은 서버(createPaidOrder)가 결제를 검증한 뒤 처리한다.
class PaymentService {
  PaymentService._();

  /// 결제 완료 후 SDK가 이 주소로 이동하면 웹뷰가 가로채 결과를 파싱한다(실제 로드 안 함).
  static const String redirectUrl = 'https://ewos.portone.redirect/complete';

  /// paymentId는 앱에서 발급하고 서버가 이 값으로 PortOne에 결제를 조회·검증한다.
  static String newPaymentId() {
    final String rand = Random().nextInt(0x7fffffff).toRadixString(16);
    return 'ewos_${DateTime.now().millisecondsSinceEpoch}_$rand';
  }

  /// 결제창을 띄우고 결과를 돌려준다. 성공(code 없음)이면 ok=true.
  static Future<PaymentResult> requestPayment(
    BuildContext context, {
    required String paymentId,
    required String orderName,
    required int amount,
  }) async {
    final PaymentResult? res = await Navigator.of(context).push<PaymentResult>(
      MaterialPageRoute<PaymentResult>(
        builder: (BuildContext _) => _PaymentWebView(
          paymentId: paymentId,
          orderName: orderName,
          amount: amount,
        ),
      ),
    );
    return res ?? const PaymentResult(false, message: '결제가 취소되었습니다.');
  }
}

/// PortOne 결제창을 로드하는 전체 화면 웹뷰. redirectUrl로의 이동을 가로채 결과를 반환한다.
class _PaymentWebView extends StatefulWidget {
  const _PaymentWebView({
    required this.paymentId,
    required this.orderName,
    required this.amount,
  });

  final String paymentId;
  final String orderName;
  final int amount;

  @override
  State<_PaymentWebView> createState() => _PaymentWebViewState();
}

class _PaymentWebViewState extends State<_PaymentWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (NavigationRequest req) {
          if (req.url.startsWith(PaymentService.redirectUrl)) {
            _finish(Uri.parse(req.url));
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadHtmlString(_html());
  }

  void _finish(Uri uri) {
    if (!mounted) return;
    final String? code = uri.queryParameters['code'];
    final String? message = uri.queryParameters['message'];
    Navigator.of(context).pop(code == null || code.isEmpty
        ? const PaymentResult(true)
        : PaymentResult(false, message: message ?? '결제에 실패했습니다.'));
  }

  /// PortOne 브라우저 SDK를 로드하고 결제를 요청하는 인라인 HTML.
  String _html() {
    final String config = jsonEncode(<String, dynamic>{
      'storeId': PaymentConfig.storeId,
      'channelKey': PaymentConfig.channelKey,
      'paymentId': widget.paymentId,
      'orderName': widget.orderName,
      'totalAmount': widget.amount,
      'currency': 'KRW',
      'payMethod': 'CARD',
      'redirectUrl': PaymentService.redirectUrl,
    });
    const String r = PaymentService.redirectUrl;
    return '''
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script src="https://cdn.portone.io/v2/browser-sdk.js"></script></head>
<body><script>
function q(o){return Object.keys(o||{}).map(function(k){
  return encodeURIComponent(k)+'='+encodeURIComponent(o[k]);}).join('&');}
PortOne.requestPayment($config).then(function(res){
  location.href='$r?'+q(res);
}).catch(function(e){
  location.href='$r?code=SDK_ERROR&message='+encodeURIComponent((e&&e.message)||'error');
});
</script></body></html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('결제')),
      body: WebViewWidget(controller: _controller),
    );
  }
}
