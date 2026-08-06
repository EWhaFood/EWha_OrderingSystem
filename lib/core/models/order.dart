import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/order_status.dart';

/// 발주 품목. 단가는 주문 시점 스냅샷이라 이후 상품 가격 변동에 영향받지 않는다.
class OrderItem {
  const OrderItem({
    required this.productId,
    required this.name,
    required this.qty,
    required this.unitPrice,
  });

  final String productId;
  final String name;
  final int qty;
  final int unitPrice;

  int get amount => qty * unitPrice;

  factory OrderItem.fromMap(Map<String, dynamic> data) {
    return OrderItem(
      productId: data['productId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      qty: (data['qty'] as num?)?.toInt() ?? 0,
      unitPrice: (data['unitPrice'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'productId': productId,
      'name': name,
      'qty': qty,
      'unitPrice': unitPrice,
      'amount': amount,
    };
  }
}

/// 상태 변경 이력 한 건.
class StatusHistory {
  const StatusHistory({
    required this.status,
    required this.byUid,
    required this.at,
    this.reason,
  });

  final OrderStatus status;
  final String byUid;
  final Timestamp at;
  final String? reason;

  factory StatusHistory.fromMap(Map<String, dynamic> data) {
    return StatusHistory(
      status: OrderStatus.fromCode(data['status'] as String? ?? 'new'),
      byUid: data['byUid'] as String? ?? '',
      at: data['at'] as Timestamp? ?? Timestamp.now(),
      reason: data['reason'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'status': status.code,
      'byUid': byUid,
      'at': at,
      if (reason != null) 'reason': reason,
    };
  }
}

/// 발주. 앱 발주와 카페24 몰 주문이 공통 스키마로 이 컬렉션에 적재된다.
class Order {
  const Order({
    required this.id,
    required this.orderNo,
    required this.source,
    required this.status,
    required this.items,
    required this.totalAmount,
    this.partnerId,
    this.partnerName,
    this.shippingAddress,
    this.memo,
    this.internalMemo,
    this.cafe24OrderId,
    this.history = const <StatusHistory>[],
    this.createdAt,
    this.processDate,
    this.isNextDay = false,
    this.desiredDeliveryDate,
  });

  final String id;
  final String orderNo;
  final OrderSource source;
  final OrderStatus status;
  final List<OrderItem> items;
  final int totalAmount;

  /// 거래처 문서 ID. 미매핑 카페24 주문은 null (운영자에게만 "미분류"로 표시).
  final String? partnerId;
  final String? partnerName;
  final String? shippingAddress;

  /// 거래처가 입력한 요청 메모.
  final String? memo;

  /// 운영자 전용 메모. 거래처에게 보이지 않는다.
  final String? internalMemo;
  final String? cafe24OrderId;
  final List<StatusHistory> history;
  final Timestamp? createdAt;

  /// 처리 기준일. 마감 시간 이후 주문 시 익일로 설정될 수 있다.
  final DateTime? processDate;

  /// 익일 처리 여부.
  final bool isNextDay;

  /// 희망 배송일 (거래처 선택).
  final DateTime? desiredDeliveryDate;

  factory Order.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    final List<dynamic> rawItems = d['items'] as List<dynamic>? ?? <dynamic>[];
    final List<dynamic> rawHistory = d['history'] as List<dynamic>? ?? <dynamic>[];
    return Order(
      id: doc.id,
      orderNo: d['orderNo'] as String? ?? '',
      source: OrderSource.fromCode(d['source'] as String? ?? 'app'),
      status: OrderStatus.fromCode(d['status'] as String? ?? 'new'),
      items: rawItems
          .map((dynamic i) => OrderItem.fromMap(i as Map<String, dynamic>))
          .toList(),
      totalAmount: (d['totalAmount'] as num?)?.toInt() ?? 0,
      partnerId: d['partnerId'] as String?,
      partnerName: d['partnerName'] as String?,
      shippingAddress: d['shippingAddress'] as String?,
      memo: d['memo'] as String?,
      internalMemo: d['internalMemo'] as String?,
      cafe24OrderId: d['cafe24OrderId'] as String?,
      history: rawHistory
          .map((dynamic h) => StatusHistory.fromMap(h as Map<String, dynamic>))
          .toList(),
      createdAt: d['createdAt'] as Timestamp?,
      processDate: (d['processDate'] as Timestamp?)?.toDate(),
      isNextDay: d['isNextDay'] as bool? ?? false,
      desiredDeliveryDate: (d['desiredDeliveryDate'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'orderNo': orderNo,
      'source': source.code,
      'status': status.code,
      'items': items.map((OrderItem i) => i.toMap()).toList(),
      'totalAmount': totalAmount,
      'partnerId': partnerId,
      'partnerName': partnerName,
      'shippingAddress': shippingAddress,
      'memo': memo,
      'internalMemo': internalMemo,
      'cafe24OrderId': cafe24OrderId,
      'history': history.map((StatusHistory h) => h.toMap()).toList(),
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'processDate': processDate != null ? Timestamp.fromDate(processDate!) : null,
      'isNextDay': isNextDay,
      'desiredDeliveryDate': desiredDeliveryDate != null
          ? Timestamp.fromDate(desiredDeliveryDate!)
          : null,
    };
  }
}
