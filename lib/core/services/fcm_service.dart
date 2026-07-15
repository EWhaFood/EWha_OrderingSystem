import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 백그라운드/종료 상태 메시지 핸들러. main에서 onBackgroundMessage로 등록한다.
/// notification 페이로드가 있으면 OS가 시스템 알림을 자동 표시하므로 여기선 별도 표시를 하지 않는다.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 데이터 전용 후속 처리가 필요해지면 이곳에서 한다. 표시는 OS가 담당.
}

/// FCM 수신 전반을 담당한다: 권한, 토큰 등록/갱신/제거, 포그라운드 표시, 탭 딥링크.
class FcmService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// 알림 탭으로 열린 발주의 orderId. 홈/상세 화면이 구독해 이동한다 (EWOS-14/15 연동).
  static final ValueNotifier<String?> pendingOrderId =
      ValueNotifier<String?>(null);

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'orders',
    '발주 알림',
    description: '새 발주 및 상태 변경 알림',
    importance: Importance.high,
  );

  /// 앱 시작 후 1회 호출. 권한 요청, 로컬 알림 초기화, 메시지 리스너 등록,
  /// 종료 상태에서 알림 탭으로 열렸는지(getInitialMessage) 확인.
  static Future<void> init() async {
    await FirebaseMessaging.instance.requestPermission();
    await _initLocal();
    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    final RemoteMessage? initial =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleTap(initial);
  }

  static Future<void> _initLocal() async {
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      settings: const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (NotificationResponse r) {
        if (r.payload != null) pendingOrderId.value = r.payload;
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  /// 포그라운드에서는 OS가 알림을 표시하지 않으므로 로컬 알림으로 직접 띄운다.
  static Future<void> _showForeground(RemoteMessage message) async {
    final RemoteNotification? n = message.notification;
    if (n == null) return;
    await _local.show(
      id: message.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: message.data['orderId'] as String?,
    );
  }

  static void _handleTap(RemoteMessage message) {
    final String? orderId = message.data['orderId'] as String?;
    if (orderId != null) pendingOrderId.value = orderId;
  }

  /// 로그인 사용자의 기기 토큰을 users.fcmTokens에 저장하고 갱신을 구독한다.
  static Future<void> registerToken(String uid) async {
    final String? token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _saveToken(uid, token);
    FirebaseMessaging.instance.onTokenRefresh
        .listen((String t) => _saveToken(uid, t));
  }

  static Future<void> _saveToken(String uid, String token) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      <String, dynamic>{
        'fcmTokens': FieldValue.arrayUnion(<String>[token]),
      },
      SetOptions(merge: true),
    );
  }

  /// 로그아웃 시 현재 기기 토큰을 제거해 이후 푸시 수신을 막는다.
  static Future<void> unregisterToken(String uid) async {
    final String? token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      <String, dynamic>{
        'fcmTokens': FieldValue.arrayRemove(<String>[token]),
      },
      SetOptions(merge: true),
    );
  }
}
