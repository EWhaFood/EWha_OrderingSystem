import 'package:cloud_functions/cloud_functions.dart';

/// 상품 동기화 결과: 동기화한 몰 수와 상품 수.
typedef SyncResult = ({int malls, int products});

/// 카페24 연동 관련 운영자 액션. 앱은 카페24를 직접 호출하지 않고 Functions를 거친다.
class Cafe24Service {
  // Functions가 서울 리전에 배포되므로 리전을 명시해야 호출이 라우팅된다.
  static final FirebaseFunctions _fns =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// 등록된 모든 몰의 카페24 상품을 products 컬렉션으로 동기화한다(운영자 전용).
  static Future<SyncResult> syncProducts() async {
    final HttpsCallable callable = _fns.httpsCallable('syncCafe24Products');
    final HttpsCallableResult<dynamic> result = await callable.call<dynamic>();
    final Map<dynamic, dynamic> data = result.data as Map<dynamic, dynamic>;
    return (
      malls: (data['malls'] as num?)?.toInt() ?? 0,
      products: (data['products'] as num?)?.toInt() ?? 0,
    );
  }
}
