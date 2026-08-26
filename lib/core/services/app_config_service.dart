import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 앱 시작 게이트 판정 종류.
enum AppGateType { ok, update, maintenance }

/// 시작 게이트 판정 결과. blocked=true면 진입을 막고 안내 화면을 띄운다.
class AppGateStatus {
  const AppGateStatus(this.type, {this.message, this.updateUrl});

  final AppGateType type;
  final String? message;
  final String? updateUrl;

  bool get blocked => type != AppGateType.ok;

  static const AppGateStatus ok = AppGateStatus(AppGateType.ok);
}

/// 원격 설정(settings/appConfig)으로 강제 업데이트·점검을 판정한다(EWOS-42).
/// 미로그인 시작 시점에도 읽혀야 하므로 appConfig 문서는 공개 read로 열려 있다.
class AppConfigService {
  static Future<AppGateStatus> check() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection('settings')
          .doc('appConfig')
          .get();
      final Map<String, dynamic>? data = snap.data();
      if (data == null) return AppGateStatus.ok;

      if (data['maintenance'] == true) {
        return AppGateStatus(AppGateType.maintenance,
            message: data['maintenanceMessage'] as String?);
      }

      final String? minVersion = data['minVersion'] as String?;
      if (minVersion != null && minVersion.isNotEmpty) {
        final PackageInfo info = await PackageInfo.fromPlatform();
        if (isVersionBelow(info.version, minVersion)) {
          return AppGateStatus(AppGateType.update,
              message: data['updateMessage'] as String?,
              updateUrl: data['updateUrl'] as String?);
        }
      }
      return AppGateStatus.ok;
    } catch (_) {
      // 설정을 못 읽어도 앱 진입은 막지 않는다(가용성 우선).
      return AppGateStatus.ok;
    }
  }

  /// current < min 이면 true. "1.0.0+3" 같은 빌드 접미사는 무시하고 major.minor.patch만 비교.
  static bool isVersionBelow(String current, String min) {
    final List<int> c = _parse(current);
    final List<int> m = _parse(min);
    for (int i = 0; i < 3; i++) {
      if (c[i] != m[i]) return c[i] < m[i];
    }
    return false;
  }

  static List<int> _parse(String v) {
    final List<String> parts = v.split('+').first.split('.');
    return List<int>.generate(
        3, (int i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0);
  }
}
