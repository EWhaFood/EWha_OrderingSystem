import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../core/models/order.dart' as model; // model 접두어 추가

class StatsSummary {
  final Map<String, int> dailyAmount;
  final Map<String, int> dailyCount;
  final Map<String, int> partnerAmount;
  final Map<String, int> itemQty;
  final Map<String, int> sourceCount;
  final int totalAmount;
  final int totalCount;

  StatsSummary({
    required this.dailyAmount,
    required this.dailyCount,
    required this.partnerAmount,
    required this.itemQty,
    required this.sourceCount,
    required this.totalAmount,
    required this.totalCount,
  });
}

class StatsService {
  static Future<StatsSummary> getStats(DateTimeRange range) async {
    final start = Timestamp.fromDate(DateTime(range.start.year, range.start.month, range.start.day));
    final end = Timestamp.fromDate(DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59));

    final query = FirebaseFirestore.instance
        .collection('orders')
        .where('createdAt', isGreaterThanOrEqualTo: start)
        .where('createdAt', isLessThanOrEqualTo: end);

    final snapshot = await query.get();
    // model.Order를 명시적으로 사용하여 충돌 방지
    final orders = snapshot.docs.map((doc) => model.Order.fromDoc(doc)).toList();

    Map<String, int> dailyAmount = {};
    Map<String, int> dailyCount = {};
    Map<String, int> partnerAmount = {};
    Map<String, int> itemQty = {};
    Map<String, int> sourceCount = {'app': 0, 'cafe24': 0};
    int totalAmount = 0;

    for (var order in orders) {
      if (order.createdAt == null) continue;
      
      final dateStr = _formatDate(order.createdAt!.toDate());
      dailyAmount[dateStr] = (dailyAmount[dateStr] ?? 0) + (order.totalAmount as int);
      dailyCount[dateStr] = (dailyCount[dateStr] ?? 0) + 1;

      final pName = order.partnerName ?? '미분류';
      partnerAmount[pName] = (partnerAmount[pName] ?? 0) + (order.totalAmount as int);

      for (var item in order.items) {
        itemQty[item.name] = (itemQty[item.name] ?? 0) + (item.qty as int);
      }

      final source = order.source.code;
      sourceCount[source] = (sourceCount[source] ?? 0) + 1;
      
      totalAmount += (order.totalAmount as int);
    }

    return StatsSummary(
      dailyAmount: dailyAmount,
      dailyCount: dailyCount,
      partnerAmount: partnerAmount,
      itemQty: itemQty,
      sourceCount: sourceCount,
      totalAmount: totalAmount,
      totalCount: orders.length,
    );
  }

  static String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
