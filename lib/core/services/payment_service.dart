import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/payment_config.dart';

/// 결제 수단 (EWOS-52 카드 / EWOS-54 카카오페이·네이버페이).
enum PaymentMethod {
  card('카드', Icons.credit_card),
  kakaopay('카카오페이', Icons.chat_bubble_outline),
  naverpay('네이버페이', Icons.shopping_bag_outlined);

  const PaymentMethod(this.label, this.icon);

  final String label;
  final IconData icon;

  /// PortOne V2 requestPayment에 넣을 결제수단 설정.
  Map<String, dynamic> toConfig() {
    switch (this) {
      case PaymentMethod.card:
        return <String, dynamic>{'payMethod': 'CARD'};
      case PaymentMethod.kakaopay:
        return <String, dynamic>{
          'payMethod': 'EASY_PAY',
          'easyPay': <String, dynamic>{'easyPayProvider': 'KAKAOPAY'},
        };
      case PaymentMethod.naverpay:
        return <String, dynamic>{
          'payMethod': 'EASY_PAY',
          'easyPay': <String, dynamic>{'easyPayProvider': 'NAVERPAY'},
        };
    }
  }
}

/// 결제 결과. ok=true면 결제 성공(서버 검증은 createPaidOrder에서 별도 수행).
class PaymentResult {
  const PaymentResult(this.ok, {this.message});

  final bool ok;
  final String? message;
}

/// PortOne V2 간편결제 (EWOS-52/54). 브라우저 SDK를 웹뷰로 로드해 결제창을 띄운다.
/// 카카오페이·네이버페이는 외부 앱으로 전환되므로 웹뷰가 앱 스킴을 가로채 실행한다.
class PaymentService {
  PaymentService._();

  /// 결제 완료 후 SDK가 이 주소로 이동하면 웹뷰가 가로채 결과를 파싱한다(실제 로드 안 함).
  static const String redirectUrl = 'https://ewos.portone.redirect/complete';

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
    required PaymentMethod method,
  }) async {
    final PaymentResult? res = await Navigator.of(context).push<PaymentResult>(
      MaterialPageRoute<PaymentResult>(
        builder: (BuildContext _) => _PaymentWebView(
          paymentId: paymentId,
          orderName: orderName,
          amount: amount,
          method: method,
        ),
      ),
    );
    return res ?? const PaymentResult(false, message: '결제가 취소되었습니다.');
  }
}

/// PortOne 결제창을 로드하는 전체 화면 웹뷰. redirectUrl 이동을 가로채 결과를 반환하고,
/// http(s)가 아닌 스킴(카카오페이·네이버페이 앱 등)은 외부 앱으로 실행한다.
class _PaymentWebView extends StatefulWidget {
  const _PaymentWebView({
    required this.paymentId,
    required this.orderName,
    required this.amount,
    required this.method,
  });

  final String paymentId;
  final String orderName;
  final int amount;
  final PaymentMethod method;

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
          final String url = req.url;
          if (url.startsWith(PaymentService.redirectUrl)) {
            _finish(Uri.parse(url));
            return NavigationDecision.prevent;
          }
          // 카카오페이·네이버페이 등 외부 앱 스킴은 웹뷰가 못 여니 외부로 실행한다.
          final Uri? uri = Uri.tryParse(url);
          if (uri != null && !_isWebScheme(uri.scheme)) {
            _launchExternal(uri);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadHtmlString(_html());
  }

  bool _isWebScheme(String scheme) =>
      scheme == 'http' ||
      scheme == 'https' ||
      scheme == 'about' ||
      scheme == 'data' ||
      scheme == 'blob';

  void _finish(Uri uri) {
    if (!mounted) return;
    final String? code = uri.queryParameters['code'];
    final String? message = uri.queryParameters['message'];
    Navigator.of(context).pop(code == null || code.isEmpty
        ? const PaymentResult(true)
        : PaymentResult(false, message: message ?? '결제에 실패했습니다.'));
  }

  /// 외부 앱(카카오톡·네이버 등) 실행. intent:// URL은 fallback URL을 뽑아 시도한다.
  Future<void> _launchExternal(Uri uri) async {
    Uri target = uri;
    if (uri.scheme == 'intent') {
      final Match? m =
          RegExp(r'browser_fallback_url=([^;]+)').firstMatch(uri.toString());
      if (m != null) {
        target = Uri.parse(Uri.decodeComponent(m.group(1)!));
      }
    }
    try {
      await launchUrl(target, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 외부 앱 미설치·스킴 처리 실패 — 무시(사용자가 다른 수단 선택 가능).
    }
  }

  /// PortOne 브라우저 SDK를 로드하고 결제를 요청하는 인라인 HTML.
  String _html() {
    final Map<String, dynamic> cfg = <String, dynamic>{
      'storeId': PaymentConfig.storeId,
      'channelKey': PaymentConfig.channelKey,
      'paymentId': widget.paymentId,
      'orderName': widget.orderName,
      'totalAmount': widget.amount,
      'currency': 'KRW',
      'redirectUrl': PaymentService.redirectUrl,
      'appScheme': PaymentConfig.appScheme,
      ...widget.method.toConfig(),
    };
    final String config = jsonEncode(cfg);
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
      appBar: AppBar(title: Text('${widget.method.label} 결제')),
      body: WebViewWidget(controller: _controller),
    );
  }
}
