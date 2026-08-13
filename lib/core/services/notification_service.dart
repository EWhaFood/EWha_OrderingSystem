import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification.dart';

class NotificationService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// 사용자의 알림 목록을 최신순으로 가져오는 스트림
  static Stream<List<AppNotification>> watch(String uid) {
    return _db
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(100) // 최근 100건만 유지
        .snapshots()
        .map((snap) => snap.docs.map(AppNotification.fromDoc).toList());
  }

  /// 읽지 않은 알림 개수를 가져오는 스트림
  static Stream<int> watchUnreadCount(String uid) {
    return _db
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// 알림을 읽음 처리
  static Future<void> markAsRead(String notificationId) async {
    await _db.collection('notifications').doc(notificationId).update({
      'isRead': true,
    });
  }

  /// 모든 알림을 읽음 처리
  static Future<void> markAllAsRead(String uid) async {
    final snap = await _db
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .get();

    if (snap.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }
}
