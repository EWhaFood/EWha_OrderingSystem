/// PortOne 결제 설정 (EWOS-52).
///
/// storeId·channelKey는 공개값이라 클라이언트에 둬도 되지만, 저장소 커밋 대신
/// 빌드 시 주입한다: `flutter build ... --dart-define=PORTONE_STORE_ID=... --dart-define=PORTONE_CHANNEL_KEY=...`
/// API secret은 절대 여기 두지 않는다(Functions 전용).
///
/// 값이 없으면 [isConfigured]가 false라 간편결제 버튼이 숨겨지고 계좌이체만 노출된다.
class PaymentConfig {
  PaymentConfig._();

  static const String storeId =
      String.fromEnvironment('PORTONE_STORE_ID');
  static const String channelKey =
      String.fromEnvironment('PORTONE_CHANNEL_KEY');

  /// 외부 간편결제 앱에서 복귀할 때 쓰는 커스텀 스킴(안드로이드 매니페스트에 등록 필요).
  static const String appScheme = 'ewhaorder';

  static bool get isConfigured => storeId.isNotEmpty && channelKey.isNotEmpty;
}
