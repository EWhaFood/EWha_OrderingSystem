import 'package:flutter/foundation.dart';

/// 발주 담기 상태. productId → 수량.
/// 화면을 벗어났다 돌아와도 유지되도록 앱 수명 동안 살아있는 단일 인스턴스로 둔다.
/// (제출 성공 시 clear로 비운다.)
class Cart {
  Cart._();

  static final ValueNotifier<Map<String, int>> items =
      ValueNotifier<Map<String, int>>(<String, int>{});

  static int qtyOf(String productId) => items.value[productId] ?? 0;

  static bool get isEmpty => items.value.isEmpty;

  /// 선택된 품목 종류 수.
  static int get lineCount => items.value.length;

  /// 담긴 전체 수량 합.
  static int get totalQty =>
      items.value.values.fold(0, (int sum, int q) => sum + q);

  /// 수량을 delta만큼 증감한다. 0 이하가 되면 목록에서 제거한다.
  static void add(String productId, int delta) {
    setQty(productId, qtyOf(productId) + delta);
  }

  static void setQty(String productId, int qty) {
    final Map<String, int> next = Map<String, int>.from(items.value);
    if (qty > 0) {
      next[productId] = qty;
    } else {
      next.remove(productId);
    }
    items.value = next;
  }

  static void remove(String productId) => setQty(productId, 0);

  static void clear() => items.value = <String, int>{};
}
