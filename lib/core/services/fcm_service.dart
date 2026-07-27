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
  /// 토큰 등록이 실패해도 화면 진입을 막지 않되, 원인을 알 수 있게 로그를 남긴다.
  static Future<void> registerToken(String uid) async {
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        debugPrint('FCM 토큰 발급 실패 (Play 서비스/네트워크 확인 필요)');
        return;
      }
      await _saveToken(uid, token);
    } catch (e) {
      debugPrint('FCM 토큰 등록 실패: $e');
    }
    FirebaseMessaging.instance.onTokenRefresh
        .listen((String t) => _saveToken(uid, t));
  }

  /// fcmTokens 배열에 토큰을 추가한다.
  /// merge + arrayUnion이라 필드가 없으면 새로 만들고, 이미 있으면 중복 없이 덧붙인다.
  static Future<void> _saveToken(String uid, String token) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        <String, dynamic>{
          'fcmTokens': FieldValue.arrayUnion(<String>[token]),
        },
        SetOptions(merge: true),
      );
      debugPrint('FCM 토큰 등록 완료: ${token.substring(0, 12)}...');
    } catch (e) {
      // 보안 규칙 위반(권한)·오프라인 등. 푸시만 못 받을 뿐 앱 사용은 계속 가능해야 한다.
      debugPrint('fcmTokens 저장 실패: $e');
    }
  }

  /// 이 기기가 알림 대상인지(users.fcmTokens에 현재 기기 토큰이 있는지) 확인한다.
  /// 설정 화면의 알림 토글 초기 상태로 쓴다.
  static Future<bool> isEnabled(String uid) async {
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token == null) return false;
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final List<String> tokens =
          (snap.data()?['fcmTokens'] as List<dynamic>?)?.cast<String>() ??
              <String>[];
      return tokens.contains(token);
    } catch (e) {
      debugPrint('알림 상태 조회 실패: $e');
      return false;
    }
  }

  /// 이 기기의 알림 수신을 켜고 끈다(토큰 등록/제거).
  static Future<void> setEnabled(String uid, bool enabled) async {
    if (enabled) {
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveToken(uid, token);
    } else {
      await unregisterToken(uid);
    }
  }

  /// 로그아웃 시 현재 기기 토큰을 제거해 이후 푸시 수신을 막는다.
  /// 실패해도 로그아웃 자체는 진행되어야 하므로 예외를 삼키고 로그만 남긴다.
  static Future<void> unregisterToken(String uid) async {
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        <String, dynamic>{
          'fcmTokens': FieldValue.arrayRemove(<String>[token]),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('fcmTokens 제거 실패: $e');
    }
  }
}
