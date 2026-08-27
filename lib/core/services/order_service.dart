import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../constants/order_status.dart';
import '../models/product.dart';

/// 제출을 막아야 하는 상황(중지·삭제된 품목 등)을 화면에 전달한다.
class OrderSubmitException implements Exception {
  OrderSubmitException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 발주 생성. 단가는 제출 시점 products 가격을 스냅샷해 저장하므로
/// 이후 상품 가격이 바뀌어도 기존 주문 금액은 변하지 않는다.
class OrderService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// 마감 시간 설정 가져오기 (기본값 15:00)
  static Future<TimeOfDay> getCutoffTime() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await _db.collection('settings').doc('global').get();
      if (doc.exists) {
        final String? timeStr = doc.data()?['cutoffTime'] as String?;
        if (timeStr != null) {
          final List<String> parts = timeStr.split(':');
          if (parts.length == 2) {
            return TimeOfDay(
              hour: int.parse(parts[0]),
              minute: int.parse(parts[1]),
            );
          }
        }
      }
    } catch (e) {
      // 에러 시 기본값 반환
    }
    return const TimeOfDay(hour: 15, minute: 0);
  }

  /// 처리 기준일 계산.
  /// 마감 시간 이후거나 주말이면 다음 영업일로 설정한다.
  static DateTime calculateProcessDate(DateTime now, TimeOfDay cutoff) {
    DateTime date = DateTime(now.year, now.month, now.day);
    final DateTime cutoffDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      cutoff.hour,
      cutoff.minute,
    );

    // 마감 시간 이후면 익일로 시작
    if (now.isAfter(cutoffDateTime)) {
      date = date.add(const Duration(days: 1));
    }

    // 주말(토, 일)이면 월요일로 건너뜀
    while (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      date = date.add(const Duration(days: 1));
    }

    return date;
  }

  /// 발주번호. 클라이언트 채번이라 초 단위 + 밀리초로 충돌을 피한다.
  /// (거래처별 동시 제출 빈도가 낮아 실용상 충분하며, 필요해지면 Functions 채번으로 옮긴다.)
  static String generateOrderNo(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    final String date = '${now.year}${two(now.month)}${two(now.day)}';
    final String time = '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return '$date-$time${now.millisecond.toString().padLeft(3, '0')}';
  }

  /// 담긴 품목의 현재 상품 정보를 읽어온다. whereIn 제한(30개)을 넘으면 나눠 조회한다.
  static Future<List<Product>> fetchProducts(List<String> ids) async {
    final List<Product> result = <Product>[];
    for (int i = 0; i < ids.length; i += 30) {
      final List<String> chunk =
          ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final QuerySnapshot<Map<String, dynamic>> snap = await _db
          .collection('products')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      result.addAll(snap.docs.map(Product.fromDoc));
    }
    return result;
  }

  /// 제출 직전 품목 상태를 검증한다. 담은 뒤 운영자가 중지·삭제했을 수 있다.
  static void _verify(Map<String, int> qtys, List<Product> products) {
    final Map<String, Product> byId = <String, Product>{
      for (final Product p in products) p.id: p,
    };
    final List<String> missing = <String>[];
    final List<String> disabled = <String>[];
    for (final String id in qtys.keys) {
      final Product? p = byId[id];
      if (p == null) {
        missing.add(id);
      } else if (!p.enabled) {
        disabled.add(p.name);
      }
    }
    if (disabled.isNotEmpty) {
      throw OrderSubmitException(
          '${disabled.join(', ')} 품목이 발주 중지되었습니다. 목록에서 빼고 다시 제출해주세요.');
    }
    if (missing.isNotEmpty) {
      throw OrderSubmitException('일부 품목이 삭제되었습니다. 발주 목록을 다시 확인해주세요.');
    }
  }

  /// 상태를 변경한다. 두 운영자가 동시에 처리해도 어긋나지 않도록 트랜잭션 안에서
  /// 최신 상태를 다시 읽어 전이 규칙(OrderStatus.canTransitionTo)을 검증한다.
  static Future<void> changeStatus({
    required String orderId,
    required OrderStatus next,
    required String uid,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref =
        _db.collection('orders').doc(orderId);
    await _db.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(ref);
      if (!snap.exists) throw OrderSubmitException('발주를 찾을 수 없습니다.');
      final OrderStatus current =
          OrderStatus.fromCode(snap.data()?['status'] as String? ?? 'new');
      if (current == next) return;
      if (!current.canTransitionTo(next)) {
        throw OrderSubmitException(
            '${current.operatorLabel} → ${next.operatorLabel} 상태로는 바꿀 수 없습니다. '
            '다른 담당자가 먼저 처리했을 수 있으니 새로고침 후 확인해주세요.');
      }
      tx.update(ref, <String, dynamic>{
        'status': next.code,
        'history': FieldValue.arrayUnion(<Map<String, dynamic>>[
          <String, dynamic>{
            'status': next.code,
            'byUid': uid,
            'at': Timestamp.now(),
          },
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// 거래처의 현재 미수금(미결제·미취소 주문 합계)을 산출한다. (EWOS-44)
  /// 취소·결제완료 주문은 제외. 인덱스 부담을 피해 partnerId만 조회 후 클라이언트에서 합산.
  static Future<int> outstandingFor(String partnerId) async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection('orders')
        .where('partnerId', isEqualTo: partnerId)
        .get();
    int sum = 0;
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
      final Map<String, dynamic> d = doc.data();
      final bool paid = d['paymentStatus'] == 'paid';
      final bool canceled = d['status'] == OrderStatus.canceled.code;
      if (!paid && !canceled) sum += (d['totalAmount'] as num?)?.toInt() ?? 0;
    }
    return sum;
  }

  /// 입금 확인/취소(운영자). 주문 결제 상태를 설정한다.
  static Future<void> setOrderPaid(String orderId, bool paid) async {
    await _db.collection('orders').doc(orderId).update(<String, dynamic>{
      'paymentStatus': paid ? 'paid' : 'unpaid',
      'paidAt': paid ? Timestamp.now() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 거래처 외상 한도 설정(운영자). 0이면 무제한. (EWOS-44)
  static Future<void> setCreditLimit(String partnerId, int limit) async {
    await _db.collection('partners').doc(partnerId).update(<String, dynamic>{
      'creditLimit': limit,
    });
  }

  /// 입금 계좌 정보(후정산 안내용). settings/global에 저장. (EWOS-44)
  static Future<({String bank, String number, String holder})>
      getDepositAccount() async {
    final DocumentSnapshot<Map<String, dynamic>> doc =
        await _db.collection('settings').doc('global').get();
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return (
      bank: d['depositBank'] as String? ?? '',
      number: d['depositAccount'] as String? ?? '',
      holder: d['depositHolder'] as String? ?? '',
    );
  }

  /// 입금 확인 요청(거래처). 서버가 발주를 'requested'로 표시하고 운영자에게 푸시한다. (EWOS-44)
  static Future<void> requestPaymentConfirm(String orderId) async {
    final FirebaseFunctions fns =
        FirebaseFunctions.instanceFor(region: 'asia-northeast3');
    await fns
        .httpsCallable('requestPaymentConfirm')
        .call<dynamic>(<String, dynamic>{'orderId': orderId});
  }

  /// 입금 계좌 설정(운영자).
  static Future<void> setDepositAccount(
      String bank, String number, String holder) async {
    await _db.collection('settings').doc('global').set(<String, dynamic>{
      'depositBank': bank,
      'depositAccount': number,
      'depositHolder': holder,
    }, SetOptions(merge: true));
  }

  /// 운영자 전용 내부 메모 저장. 거래처에게는 보이지 않는다.
  static Future<void> saveInternalMemo(String orderId, String memo) async {
    await _db.collection('orders').doc(orderId).update(<String, dynamic>{
      'internalMemo': memo.trim().isEmpty ? null : memo.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 거래처에 의한 발주 취소. 트랜잭션으로 현재 상태를 검증한다.
  static Future<void> cancelOrder({
    required String orderId,
    required String uid,
    String? reason,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref =
        _db.collection('orders').doc(orderId);
    await _db.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(ref);
      if (!snap.exists) throw OrderSubmitException('발주를 찾을 수 없습니다.');
      final OrderStatus current =
          OrderStatus.fromCode(snap.data()?['status'] as String? ?? 'new');

      if (current == OrderStatus.canceled) return;
      if (!current.isCancelable) {
        throw OrderSubmitException(
            '${current.partnerLabel} 상태에서는 취소할 수 없습니다. 운영자에게 문의하세요.');
      }

      tx.update(ref, <String, dynamic>{
        'status': OrderStatus.canceled.code,
        'history': FieldValue.arrayUnion(<Map<String, dynamic>>[
          <String, dynamic>{
            'status': OrderStatus.canceled.code,
            'byUid': uid,
            'at': Timestamp.now(),
            if (reason != null) 'reason': reason,
          },
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// 간편결제(PortOne) 발주 (EWOS-52). 결제 성공 후 호출한다.
  /// Functions가 금액을 재계산하고 PortOne로 결제를 검증한 뒤에만 주문을 만든다.
  /// paymentId 기준 멱등이라 재호출해도 주문은 1건이다. 발주번호를 돌려준다.
  static Future<String> createPaidOrder({
    required String paymentId,
    required Map<String, int> qtys,
    String? shippingAddress,
    String? memo,
    DateTime? desiredDeliveryDate,
  }) async {
    final FirebaseFunctions fns =
        FirebaseFunctions.instanceFor(region: 'asia-northeast3');
    final HttpsCallableResult<dynamic> res = await fns
        .httpsCallable('createPaidOrder')
        .call<dynamic>(<String, dynamic>{
      'paymentId': paymentId,
      'qtys': qtys,
      'shippingAddress': shippingAddress,
      'memo': memo,
      'desiredDeliveryDate': desiredDeliveryDate?.millisecondsSinceEpoch,
    });
    final Map<dynamic, dynamic> data = res.data as Map<dynamic, dynamic>;
    return data['orderNo'] as String;
  }

  /// 발주를 저장하고 발주번호를 돌려준다.
  static Future<String> submit({
    required String uid,
    required String partnerId,
    required String partnerName,
    required Map<String, int> qtys,
    String? shippingAddress,
    String? memo,
    DateTime? desiredDeliveryDate,
  }) async {
    final List<Product> products = await fetchProducts(qtys.keys.toList());
    _verify(qtys, products);

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    int total = 0;
    for (final Product p in products) {
      final int qty = qtys[p.id] ?? 0;
      if (qty <= 0) continue;
      final int amount = p.price * qty;
      total += amount;
      items.add(<String, dynamic>{
        'productId': p.id,
        'name': p.name,
        'qty': qty,
        'unitPrice': p.price,
        'amount': amount,
      });
    }
    if (items.isEmpty) throw OrderSubmitException('담긴 품목이 없습니다.');

    final DateTime now = DateTime.now();
    final TimeOfDay cutoff = await getCutoffTime();
    final DateTime processDate = calculateProcessDate(now, cutoff);
    final bool isNextDay = processDate.day != now.day ||
        processDate.month != now.month ||
        processDate.year != now.year;

    final String orderNo = generateOrderNo(now);
    await _db.collection('orders').add(<String, dynamic>{
      'orderNo': orderNo,
      'source': OrderSource.app.code,
      'status': OrderStatus.newOrder.code,
      'partnerId': partnerId,
      'partnerName': partnerName,
      'items': items,
      'totalAmount': total,
      'shippingAddress': shippingAddress,
      'memo': memo,
      'processDate': Timestamp.fromDate(processDate),
      'isNextDay': isNextDay,
      'paymentStatus': 'unpaid', // 앱 발주는 외상(미결제)으로 시작 (EWOS-44)
      'desiredDeliveryDate': desiredDeliveryDate != null
          ? Timestamp.fromDate(desiredDeliveryDate)
          : null,
      // 배열 안에는 serverTimestamp를 쓸 수 없어 클라이언트 시각을 기록한다.
      'history': <Map<String, dynamic>>[
        <String, dynamic>{
          'status': OrderStatus.newOrder.code,
          'byUid': uid,
          'at': Timestamp.now(),
        },
      ],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return orderNo;
  }
}
