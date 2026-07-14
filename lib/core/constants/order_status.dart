/// 발주 처리 상태. 카페24 주문 상태가 아니라 우리 내부 처리 상태다.
/// 전이 규칙: new → processing → shipping → done, new ↔ hold.
/// done 이후 변경 불가. 역방향 전이는 운영자만.
enum OrderStatus {
  newOrder('new', '신규', '접수됨', 1),
  processing('processing', '처리중', '준비중', 2),
  shipping('shipping', '배송중', '배송중', 3),
  done('done', '완료', '완료', 4),
  hold('hold', '보류', '접수됨', 1);

  const OrderStatus(this.code, this.operatorLabel, this.partnerLabel, this.step);

  /// Firestore에 저장되는 문자열 값.
  final String code;

  /// 운영자 앱에 표시하는 라벨.
  final String operatorLabel;

  /// 거래처 앱에 표시하는 라벨.
  final String partnerLabel;

  /// 진행 단계 (1=접수, 2=준비중, 3=배송, 4=완료).
  final int step;

  static OrderStatus fromCode(String code) {
    return OrderStatus.values.firstWhere(
      (OrderStatus s) => s.code == code,
      orElse: () => OrderStatus.newOrder,
    );
  }

  /// 이 상태에서 전이 가능한 다음 상태 목록. UI 버튼 노출에 사용.
  List<OrderStatus> get allowedTransitions {
    switch (this) {
      case OrderStatus.newOrder:
        return <OrderStatus>[OrderStatus.processing, OrderStatus.hold];
      case OrderStatus.processing:
        return <OrderStatus>[OrderStatus.shipping];
      case OrderStatus.shipping:
        return <OrderStatus>[OrderStatus.done];
      case OrderStatus.hold:
        return <OrderStatus>[OrderStatus.newOrder];
      case OrderStatus.done:
        return <OrderStatus>[];
    }
  }

  bool canTransitionTo(OrderStatus next) => allowedTransitions.contains(next);
}

/// 발주 유입 채널. 앱 발주와 카페24 몰 주문을 동일하게 취급하되 출처만 구분.
enum OrderSource {
  app('app', '앱'),
  cafe24('cafe24', '카페24');

  const OrderSource(this.code, this.label);

  final String code;
  final String label;

  static OrderSource fromCode(String code) {
    return OrderSource.values.firstWhere(
      (OrderSource s) => s.code == code,
      orElse: () => OrderSource.app,
    );
  }
}
