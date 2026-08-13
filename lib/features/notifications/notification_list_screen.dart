import 'package:flutter/material.dart';
import '../../core/models/notification.dart';
import '../../core/services/notification_service.dart';
import '../../core/utils/format.dart';
import '../orders/operator_order_detail_screen.dart';
import '../orders/partner_order_detail_screen.dart';
import '../../core/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationListScreen extends StatelessWidget {
  const NotificationListScreen({super.key, required this.uid, this.isOperator = false});

  final String uid;
  final bool isOperator;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림함'),
        actions: [
          TextButton(
            onPressed: () => NotificationService.markAllAsRead(uid),
            child: const Text('모두 읽음'),
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: NotificationService.watch(uid),
        builder: (context, snap) {
          if (snap.hasError) {
            debugPrint('Notification Error: ${snap.error}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('알림을 불러오지 못했습니다.'),
                    const SizedBox(height: 8),
                    Text(
                      '${snap.error}',
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final notifications = snap.data!;
          if (notifications.isEmpty) {
            return const Center(
              child: Text('알림 내역이 없습니다.', style: TextStyle(color: Colors.grey)),
            );
          }

          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final n = notifications[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: n.isRead ? Colors.grey.shade200 : Theme.of(context).primaryColor.withOpacity(0.1),
                  child: Icon(
                    Icons.notifications_outlined,
                    color: n.isRead ? Colors.grey : Theme.of(context).primaryColor,
                  ),
                ),
                title: Text(
                  n.title,
                  style: TextStyle(
                    fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(n.body, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      formatListTime(n.createdAt),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                onTap: () => _onTapNotification(context, n),
                tileColor: n.isRead ? null : Colors.blue.withOpacity(0.03),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _onTapNotification(BuildContext context, AppNotification n) async {
    // 1. 읽음 처리
    if (!n.isRead) {
      await NotificationService.markAsRead(n.id);
    }

    // 2. 관련 발주 상세로 이동
    if (n.orderId != null && context.mounted) {
      if (isOperator) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OperatorOrderDetailScreen(uid: uid, orderId: n.orderId!),
          ),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PartnerOrderDetailScreen(uid: uid, orderId: n.orderId!),
          ),
        );
      }
    }
  }
}
