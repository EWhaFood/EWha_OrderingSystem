import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/models/app_user.dart';
import 'core/models/partner.dart';
import 'core/services/app_config_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/fcm_service.dart';
import 'features/admin/operator_main_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/orders/partner_home_screen.dart';

class EwhaOrderingApp extends StatelessWidget {
  const EwhaOrderingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '이화 발주',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF185FA5)),
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'),
      ],
      locale: const Locale('ko', 'KR'),
      home: const _StartupGate(),
    );
  }
}

/// 앱 시작 게이트(EWOS-42). 원격 설정으로 점검/강제 업데이트를 먼저 판정하고,
/// 정상일 때만 인증 게이트로 진입시킨다. 설정을 못 읽으면 그냥 통과(가용성 우선).
class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppGateStatus>(
      future: AppConfigService.check(),
      builder: (BuildContext context, AsyncSnapshot<AppGateStatus> snapshot) {
        if (!snapshot.hasData) return const _SplashScreen();
        final AppGateStatus status = snapshot.data!;
        if (status.blocked) return _GateScreen(status: status);
        return const AuthGate();
      },
    );
  }
}

/// 점검 중·강제 업데이트 안내 화면. 진입을 막는 전체 화면이다.
class _GateScreen extends StatelessWidget {
  const _GateScreen({required this.status});

  final AppGateStatus status;

  bool get _isMaintenance => status.type == AppGateType.maintenance;

  Future<void> _openStore() async {
    final String? url = status.updateUrl;
    if (url == null || url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final String title = _isMaintenance ? '서비스 점검 중' : '업데이트가 필요합니다';
    final String body = status.message ??
        (_isMaintenance
            ? '더 나은 서비스를 위해 점검 중입니다. 잠시 후 다시 시도해 주세요.'
            : '원활한 이용을 위해 최신 버전으로 업데이트해 주세요.');
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(_isMaintenance ? Icons.build_outlined : Icons.system_update,
                  size: 44, color: const Color(0xFF888780)),
              const SizedBox(height: 16),
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text(body, textAlign: TextAlign.center),
              if (!_isMaintenance &&
                  status.updateUrl != null &&
                  status.updateUrl!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _openStore,
                  child: const Text('업데이트하기'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 스플래시 겸 인증 게이트. 로그인 상태와 role에 따라 화면을 분기한다.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (BuildContext context, AsyncSnapshot<User?> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }
        final User? user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }
        return _RoleRouter(uid: user.uid);
      },
    );
  }
}

/// users/{uid} 문서를 읽어 role별로 라우팅한다. 진입 시 이 기기의 FCM 토큰을 등록한다.
/// operator는 바로 홈, partner는 활성 여부 확인 게이트로 넘긴다.
class _RoleRouter extends StatefulWidget {
  const _RoleRouter({required this.uid});

  final String uid;

  @override
  State<_RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<_RoleRouter> {
  @override
  void initState() {
    super.initState();
    // 로그인된 사용자의 토큰을 등록한다 (실패해도 화면 진입은 막지 않는다).
    FcmService.registerToken(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    final DocumentReference<Map<String, dynamic>> ref =
        FirebaseFirestore.instance.collection('users').doc(widget.uid);
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: ref.get(),
      builder: (BuildContext context,
          AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot) {
        if (!snapshot.hasData) {
          return const _SplashScreen();
        }
        final AppUser appUser = AppUser.fromDoc(snapshot.data!);
        if (appUser.isOperator) {
          return OperatorMainScreen(uid: widget.uid);
        }
        return _PartnerGate(uid: widget.uid, partnerId: appUser.partnerId);
      },
    );
  }
}

/// 거래처 계정의 활성 여부를 확인한다. active=false면 접근을 차단한다.
class _PartnerGate extends StatelessWidget {
  const _PartnerGate({required this.uid, required this.partnerId});

  final String uid;
  final String? partnerId;

  @override
  Widget build(BuildContext context) {
    if (partnerId == null) {
      return _BlockedScreen(
          uid: uid, message: '연결된 거래처가 없습니다. 관리자에게 문의하세요.');
    }
    final DocumentReference<Map<String, dynamic>> ref =
        FirebaseFirestore.instance.collection('partners').doc(partnerId);
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: ref.get(),
      builder: (BuildContext context,
          AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot) {
        if (!snapshot.hasData) {
          return const _SplashScreen();
        }
        final Partner partner = Partner.fromDoc(snapshot.data!);
        if (!partner.active) {
          return _BlockedScreen(
              uid: uid, message: '비활성화된 거래처 계정입니다. 관리자에게 문의하세요.');
        }
        return PartnerHome(uid: uid, partner: partner);
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// 접근 차단 안내. 로그아웃 버튼으로 로그인 화면으로 돌아갈 수 있다.
class _BlockedScreen extends StatelessWidget {
  const _BlockedScreen({required this.uid, required this.message});

  final String uid;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.lock_outline, size: 40, color: Color(0xFF888780)),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => logout(uid),
                child: const Text('로그아웃'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
