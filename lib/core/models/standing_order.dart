import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum StandingOrderCycleType {
  weekly('weekly', '요일 지정'),
  interval('interval', '간격 지정');

  const StandingOrderCycleType(this.code, this.label);
  final String code;
  final String label;

  static StandingOrderCycleType fromCode(String code) {
    return StandingOrderCycleType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => StandingOrderCycleType.weekly,
    );
  }
}

class StandingOrderCycle {
  const StandingOrderCycle({
    required this.type,
    this.daysOfWeek = const [], // 1 (Mon) to 7 (Sun)
    this.intervalDays,
  });

  final StandingOrderCycleType type;
  final List<int> daysOfWeek;
  final int? intervalDays;

  factory StandingOrderCycle.fromMap(Map<String, dynamic> data) {
    return StandingOrderCycle(
      type: StandingOrderCycleType.fromCode(data['type'] as String? ?? 'weekly'),
      daysOfWeek: (data['daysOfWeek'] as List<dynamic>?)?.cast<int>() ?? [],
      intervalDays: data['intervalDays'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.code,
      'daysOfWeek': daysOfWeek,
      if (intervalDays != null) 'intervalDays': intervalDays,
    };
  }

  String get label {
    if (type == StandingOrderCycleType.weekly) {
      if (daysOfWeek.isEmpty) return '미지정';
      final days = ['월', '화', '수', '목', '금', '토', '일'];
      final sorted = List<int>.from(daysOfWeek)..sort();
      return '매주 ${sorted.map((d) => days[d - 1]).join(', ')}';
    } else {
      return '${intervalDays ?? 0}일 간격';
    }
  }
}

enum StandingOrderStatus {
  active('active', '활성'),
  paused('paused', '일시중지'),
  cancelled('cancelled', '해지');

  const StandingOrderStatus(this.code, this.label);
  final String code;
  final String label;

  static StandingOrderStatus fromCode(String code) {
    return StandingOrderStatus.values.firstWhere(
      (e) => e.code == code,
      orElse: () => StandingOrderStatus.active,
    );
  }
}

class StandingOrder {
  const StandingOrder({
    required this.id,
    required this.partnerId,
    required this.favoriteId,
    required this.favoriteName,
    required this.cycle,
    required this.preferredTime,
    required this.status,
    required this.autoConfirm,
    this.nextOrderDate,
    this.lastOrderDate,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String partnerId;
  final String favoriteId;
  final String favoriteName;
  final StandingOrderCycle cycle;
  final TimeOfDay preferredTime;
  final StandingOrderStatus status;
  final bool autoConfirm;
  final DateTime? nextOrderDate;
  final DateTime? lastOrderDate;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  factory StandingOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final timeStr = data['preferredTime'] as String? ?? '09:00';
    final timeParts = timeStr.split(':');
    
    return StandingOrder(
      id: doc.id,
      partnerId: data['partnerId'] as String? ?? '',
      favoriteId: data['favoriteId'] as String? ?? '',
      favoriteName: data['favoriteName'] as String? ?? '',
      cycle: StandingOrderCycle.fromMap(data['cycle'] as Map<String, dynamic>? ?? {}),
      preferredTime: TimeOfDay(
        hour: int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      ),
      status: StandingOrderStatus.fromCode(data['status'] as String? ?? 'active'),
      autoConfirm: true, // 항상 즉시 발주로 고정
      nextOrderDate: (data['nextOrderDate'] as Timestamp?)?.toDate(),
      lastOrderDate: (data['lastOrderDate'] as Timestamp?)?.toDate(),
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'partnerId': partnerId,
      'favoriteId': favoriteId,
      'favoriteName': favoriteName,
      'cycle': cycle.toMap(),
      'preferredTime': '${preferredTime.hour.toString().padLeft(2, '0')}:${preferredTime.minute.toString().padLeft(2, '0')}',
      'status': status.code,
      'autoConfirm': autoConfirm,
      'nextOrderDate': nextOrderDate != null ? Timestamp.fromDate(nextOrderDate!) : null,
      'lastOrderDate': lastOrderDate != null ? Timestamp.fromDate(lastOrderDate!) : null,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
