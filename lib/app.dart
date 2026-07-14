import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'core/models/app_user.dart';
import 'core/models/partner.dart';
import 'features/auth/login_screen.dart';

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
      home: const AuthGate(),
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

/// users/{uid} 문서를 읽어 role별로 라우팅한다.
/// operator는 바로 홈, partner는 활성 여부 확인 게이트로 넘긴다.
class _RoleRouter extends StatelessWidget {
  const _RoleRouter({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final DocumentReference<Map<String, dynamic>> ref =
        FirebaseFirestore.instance.collection('users').doc(uid);
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: ref.get(),
      builder: (BuildContext context,
          AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot) {
        if (!snapshot.hasData) {
          return const _SplashScreen();
        }
        final AppUser appUser = AppUser.fromDoc(snapshot.data!);
        if (appUser.isOperator) {
          return const _HomePlaceholder(label: '운영자 홈');
        }
        return _PartnerGate(partnerId: appUser.partnerId);
      },
    );
  }
}

/// 거래처 계정의 활성 여부를 확인한다. active=false면 접근을 차단한다.
class _PartnerGate extends StatelessWidget {
  const _PartnerGate({required this.partnerId});

  final String? partnerId;

  @override
  Widget build(BuildContext context) {
    if (partnerId == null) {
      return const _BlockedScreen(message: '연결된 거래처가 없습니다. 관리자에게 문의하세요.');
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
          return const _BlockedScreen(message: '비활성화된 거래처 계정입니다. 관리자에게 문의하세요.');
        }
        return _HomePlaceholder(label: '거래처 홈 (${partner.name})');
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
  const _BlockedScreen({required this.message});

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
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('로그아웃'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 역할별 홈 자리표시자. 실제 홈은 EWOS-11(거래처)·EWOS-13(운영자)에서 구현한다.
class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(label),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Center(child: Text(label)),
    );
  }
}
