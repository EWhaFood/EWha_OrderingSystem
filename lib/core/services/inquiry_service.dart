import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/inquiry.dart';

class InquiryService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// 메시지 전송
  static Future<void> sendMessage({
    required String orderId,
    required String senderId,
    required String senderRole,
    required String text,
  }) async {
    final messageData = {
      'senderId': senderId,
      'senderRole': senderRole,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
    };

    // 1. 메시지 추가
    await _db
        .collection('inquiries')
        .doc(orderId)
        .collection('messages')
        .add(messageData);

    // 2. Inquiry 요약 업데이트 (Cloud Functions에서 처리하도록 할 수도 있지만, 
    // 즉각적인 UI 반영을 위해 간단한 필드만 클라이언트에서 업데이트)
    await _db.collection('inquiries').doc(orderId).set({
      'lastMessage': text,
      'lastAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 읽음 처리 (내가 받지 않은 메시지들을 읽음으로 표시)
  static Future<void> markAsRead(String orderId, String myRole) async {
    final opponentRole = myRole == 'operator' ? 'partner' : 'operator';
    
    final unreadMessages = await _db
        .collection('inquiries')
        .doc(orderId)
        .collection('messages')
        .where('senderRole', isEqualTo: opponentRole)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = _db.batch();
    
    // 1. 메시지 읽음 처리
    for (var doc in unreadMessages.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    
    // 2. Inquiry 요약 문서의 읽지 않은 개수 초기화 (내 역할에 해당하는 카운트)
    final countField = myRole == 'operator' ? 'unreadCountOperator' : 'unreadCountPartner';
    batch.set(_db.collection('inquiries').doc(orderId), {
      countField: 0,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// 메시지 스트림
  static Stream<List<ChatMessage>> getMessages(String orderId) {
    return _db
        .collection('inquiries')
        .doc(orderId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => ChatMessage.fromDoc(doc)).toList());
  }

  /// 문의 요약 스트림 (배지 표시용)
  static Stream<Inquiry?> getInquiry(String orderId) {
    return _db
        .collection('inquiries')
        .doc(orderId)
        .snapshots()
        .map((doc) => doc.exists ? Inquiry.fromDoc(doc) : null);
  }
}
