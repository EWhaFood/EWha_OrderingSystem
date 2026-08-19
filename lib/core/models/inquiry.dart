import 'package:cloud_firestore/cloud_firestore.dart';

/// 문의 메시지 모델
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderRole,
    required this.text,
    required this.createdAt,
    this.isRead = false,
  });

  final String id;
  final String senderId;
  final String senderRole; // 'operator' | 'partner'
  final String text;
  final Timestamp createdAt;
  final bool isRead;

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return ChatMessage(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      senderRole: data['senderRole'] as String? ?? 'partner',
      text: data['text'] as String? ?? '',
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
      isRead: data['isRead'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderRole': senderRole,
      'text': text,
      'createdAt': createdAt,
      'isRead': isRead,
    };
  }
}

/// 발주별 문의 요약 모델 (orders 문서와 1:1 대응 또는 별도 컬렉션)
class Inquiry {
  Inquiry({
    required this.orderId,
    this.lastMessage,
    this.lastAt,
    this.unreadCountOperator = 0,
    this.unreadCountPartner = 0,
  });

  final String orderId;
  final String? lastMessage;
  final Timestamp? lastAt;
  final int unreadCountOperator;
  final int unreadCountPartner;

  factory Inquiry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Inquiry(
      orderId: doc.id,
      lastMessage: data['lastMessage'] as String?,
      lastAt: data['lastAt'] as Timestamp?,
      unreadCountOperator: (data['unreadCountOperator'] as num?)?.toInt() ?? 0,
      unreadCountPartner: (data['unreadCountPartner'] as num?)?.toInt() ?? 0,
    );
  }
}
