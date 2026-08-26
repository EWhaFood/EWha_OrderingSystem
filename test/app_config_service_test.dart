import 'package:flutter_test/flutter_test.dart';
import 'package:ewha_orderingsystem/core/services/app_config_service.dart';

/// EWOS-42 강제 업데이트 판정의 핵심인 버전 비교 로직 단위 테스트.
void main() {
  group('AppConfigService.isVersionBelow', () {
    test('같은 버전은 미만이 아니다', () {
      expect(AppConfigService.isVersionBelow('1.0.0', '1.0.0'), isFalse);
    });

    test('낮은 버전은 미만이다(업데이트 필요)', () {
      expect(AppConfigService.isVersionBelow('1.0.0', '1.1.0'), isTrue);
      expect(AppConfigService.isVersionBelow('0.9.9', '1.0.0'), isTrue);
      expect(AppConfigService.isVersionBelow('1.0.0', '1.0.1'), isTrue);
    });

    test('높은 버전은 미만이 아니다', () {
      expect(AppConfigService.isVersionBelow('1.2.0', '1.1.9'), isFalse);
      expect(AppConfigService.isVersionBelow('2.0.0', '1.9.9'), isFalse);
    });

    test('빌드 접미사(+N)는 무시한다', () {
      expect(AppConfigService.isVersionBelow('1.0.0+5', '1.0.0'), isFalse);
      expect(AppConfigService.isVersionBelow('1.0.0+1', '1.0.1'), isTrue);
    });

    test('자리수가 모자란 버전은 0으로 채워 비교한다', () {
      expect(AppConfigService.isVersionBelow('1.0', '1.0.0'), isFalse);
      expect(AppConfigService.isVersionBelow('1.0', '1.0.1'), isTrue);
      expect(AppConfigService.isVersionBelow('1', '1.0.0'), isFalse);
    });
  });
}
