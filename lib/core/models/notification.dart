import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.uid,
    required this.title,
    required this.body,
    required this.createdAt,
    this.orderId,
    this.isRead = false,
  });

  final String id;
  final String uid; // 수신자 UID
  final String title;
  final String body;
  final DateTime createdAt;
  final String? orderId; // 연관된 발주 ID (있을 경우)
  final bool isRead;

  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppNotification(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      orderId: data['orderId'] as String?,
      isRead: data['isRead'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'title': title,
      'body': body,
      'createdAt': Timestamp.fromDate(createdAt),
      if (orderId != null) 'orderId': orderId,
      'isRead': isRead,
    };
  }
}
