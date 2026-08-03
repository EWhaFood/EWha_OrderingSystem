import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// 발주를 저장하고 발주번호를 돌려준다.
  static Future<String> submit({
    required String uid,
    required String partnerId,
    required String partnerName,
    required Map<String, int> qtys,
    String? shippingAddress,
    String? memo,
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

    final String orderNo = generateOrderNo(DateTime.now());
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
