import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/standing_order.dart';

class StandingOrderService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<List<StandingOrder>> watch(String partnerId) {
    return _db
        .collection('standing_orders')
        .where('partnerId', isEqualTo: partnerId)
        .snapshots()
        .map((snap) => snap.docs
            .map(StandingOrder.fromDoc)
            .where((so) => so.status != StandingOrderStatus.cancelled)
            .toList());
  }

  static Future<void> save(StandingOrder standingOrder) async {
    if (standingOrder.id.isEmpty) {
      await _db.collection('standing_orders').add(standingOrder.toMap());
    } else {
      await _db
          .collection('standing_orders')
          .doc(standingOrder.id)
          .update(standingOrder.toMap());
    }
  }

  static Future<void> updateStatus(String id, StandingOrderStatus status) async {
    await _db.collection('standing_orders').doc(id).update({
      'status': status.code,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static DateTime calculateNextOrderDate(
      StandingOrderCycle cycle, DateTime from, {DateTime? lastOrderDate}) {
    final DateTime start = DateTime(from.year, from.month, from.day);
    
    if (cycle.type == StandingOrderCycleType.weekly) {
      if (cycle.daysOfWeek.isEmpty) return start;
      final sortedDays = List<int>.from(cycle.daysOfWeek)..sort();
      
      // 오늘이 포함되어 있는지 확인
      if (sortedDays.contains(start.weekday)) {
        return start;
      }
      
      // 이번 주 남은 요일 중 가장 빠른 날
      for (final day in sortedDays) {
        if (day > start.weekday) {
          return start.add(Duration(days: day - start.weekday));
        }
      }
      
      // 다음 주 첫 번째 요일
      return start.add(Duration(days: 7 - start.weekday + sortedDays.first));
    } else {
      final int interval = cycle.intervalDays ?? 1;
      if (lastOrderDate != null) {
        final last = DateTime(lastOrderDate.year, lastOrderDate.month, lastOrderDate.day);
        return last.add(Duration(days: interval));
      }
      return start; // 신규 등록 시 오늘부터 시작
    }
  }

  /// 미처리된 정기발주를 체크하여 초안을 생성한다.
  static Future<void> processStandingOrders(String partnerId, String partnerName, String uid) async {
    final now = DateTime.now();
    final snap = await _db
        .collection('standing_orders')
        .where('partnerId', isEqualTo: partnerId)
        .where('status', isEqualTo: StandingOrderStatus.active.code)
        .get();

    for (final doc in snap.docs) {
      final so = StandingOrder.fromDoc(doc);
      if (so.nextOrderDate == null) continue;

      final nextDateTime = DateTime(
        so.nextOrderDate!.year,
        so.nextOrderDate!.month,
        so.nextOrderDate!.day,
        so.preferredTime.hour,
        so.preferredTime.minute,
      );

      if (now.isAfter(nextDateTime)) {
        await _createOrderFromStandingOrder(so, partnerName, uid);
        
        final nextDate = calculateNextOrderDate(
          so.cycle,
          nextDateTime.add(const Duration(minutes: 1)),
          lastOrderDate: nextDateTime,
        );
        
        await _db.collection('standing_orders').doc(so.id).update({
          'nextOrderDate': Timestamp.fromDate(nextDate),
          'lastOrderDate': Timestamp.fromDate(nextDateTime),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  static Future<void> _createOrderFromStandingOrder(StandingOrder so, String partnerName, String uid) async {
    // 템플릿(즐겨찾기) 아이템 조회
    final favDoc = await _db.collection('favorites').doc(so.favoriteId).get();
    if (!favDoc.exists) return;

    final List<dynamic> rawItems = favDoc.data()?['items'] as List<dynamic>? ?? [];
    if (rawItems.isEmpty) return;

    final Map<String, int> qtys = {
      for (final item in rawItems) item['productId'] as String: item['qty'] as int
    };

    // 항상 즉시 '신규 발주'로 생성 (사용자 요청 반영)
    const status = 'new';
    final List<String> productIds = qtys.keys.toList();
    final products = await _fetchProducts(productIds);
    
    int total = 0;
    final List<Map<String, dynamic>> items = [];
    for (final p in products) {
      final qty = qtys[p.id] ?? 0;
      if (qty <= 0 || !p.enabled) continue; // 판매 중지 품목 자동 제외
      final int amount = p.price * qty;
      total += amount;
      items.add({
        'productId': p.id,
        'name': p.name,
        'qty': qty,
        'unitPrice': p.price,
        'amount': amount,
      });
    }

    if (items.isEmpty) return;

    // 주문 DB 적재
    await _db.collection('orders').add({
      'orderNo': 'SO-${DateTime.now().millisecondsSinceEpoch}',
      'source': 'app',
      'status': status,
      'partnerId': so.partnerId,
      'partnerName': partnerName,
      'items': items,
      'totalAmount': total,
      'history': [
        {
          'status': status,
          'byUid': 'system',
          'at': Timestamp.now(),
          'reason': '정기발주 자동 생성 (템플릿: ${so.favoriteName})',
        }
      ],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<List<_ProductStub>> _fetchProducts(List<String> ids) async {
    final List<_ProductStub> result = [];
    for (var id in ids) {
      final doc = await _db.collection('products').doc(id).get();
      if (doc.exists) {
        final d = doc.data()!;
        result.add(_ProductStub(id, d['name'], d['price'], d['enabled']));
      }
    }
    return result;
  }
}

class _ProductStub {
  final String id;
  final String name;
  final int price;
  final bool enabled;
  _ProductStub(this.id, this.name, this.price, this.enabled);
}
