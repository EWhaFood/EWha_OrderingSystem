import 'package:cloud_functions/cloud_functions.dart';

/// 운영자 전용 유지보수 액션. 테스트 데이터 삭제 등.
class MaintenanceService {
  static final FirebaseFunctions _fns =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// 테스트 데이터 삭제(운영자·테스트모드 전용). 선택한 항목만 지운다.
  /// secrets·cafe24Status·운영자 계정은 서버에서 항상 보존된다.
  static Future<Map<String, int>> clearTestData({
    bool orders = false,
    bool notifications = false,
    bool favorites = false,
    bool standingOrders = false,
    bool products = false,
    bool cafe24Products = false,
    bool partners = false,
    bool partnerUsers = false,
  }) async {
    final HttpsCallable callable = _fns.httpsCallable('clearTestData');
    final HttpsCallableResult<dynamic> result =
        await callable.call<dynamic>(<String, dynamic>{
      'orders': orders,
      'notifications': notifications,
      'favorites': favorites,
      'standingOrders': standingOrders,
      'products': products,
      'cafe24Products': cafe24Products,
      'partners': partners,
      'partnerUsers': partnerUsers,
    });
    final Map<dynamic, dynamic> deleted =
        (result.data as Map<dynamic, dynamic>)['deleted']
            as Map<dynamic, dynamic>;
    return deleted.map(
        (dynamic k, dynamic v) => MapEntry<String, int>(k as String, (v as num).toInt()));
  }
}
