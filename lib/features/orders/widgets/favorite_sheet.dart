import 'package:flutter/material.dart';

import '../../../core/models/favorite.dart';
import '../../../core/models/product.dart';
import '../../../core/services/favorite_service.dart';
import '../cart.dart';

/// 발주 즐겨찾기 시트를 연다. 저장된 묶음을 불러오거나 현재 장바구니를 새로 저장한다.
Future<void> showFavoriteSheet({
  required BuildContext context,
  required String partnerId,
  required List<Product> products,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext ctx) =>
        _FavoriteSheet(partnerId: partnerId, products: products),
  );
}

/// 즐겨찾기 목록 + 저장 진입점. 함수를 잘게 나눠 각 위젯을 50줄 이내로 유지한다.
class _FavoriteSheet extends StatelessWidget {
  const _FavoriteSheet({required this.partnerId, required this.products});

  final String partnerId;
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _header(context),
            const SizedBox(height: 8),
            _saveButton(context),
            const Divider(height: 24),
            Flexible(child: _list(context)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Text('발주 즐겨찾기', style: Theme.of(context).textTheme.titleMedium);
  }

  /// 현재 담긴 목록을 즐겨찾기로 저장. 장바구니가 비어있으면 비활성이다.
  Widget _saveButton(BuildContext context) {
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: Cart.items,
      builder: (BuildContext context, Map<String, int> items, _) {
        return OutlinedButton.icon(
          onPressed: items.isEmpty ? null : () => _promptSave(context),
          icon: const Icon(Icons.star_outline),
          label: const Text('현재 담긴 목록을 즐겨찾기로 저장'),
        );
      },
    );
  }

  Widget _list(BuildContext context) {
    return StreamBuilder<List<Favorite>>(
      stream: FavoriteService.watch(partnerId),
      builder: (BuildContext context, AsyncSnapshot<List<Favorite>> snap) {
        if (snap.hasError) {
          return _hint(context, '즐겨찾기를 불러오지 못했습니다');
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final List<Favorite> favorites = snap.data ?? <Favorite>[];
        if (favorites.isEmpty) {
          return _hint(context, '저장된 즐겨찾기가 없습니다\n담은 품목을 저장해 다음에 한 번에 불러오세요');
        }
        return ListView.separated(
          shrinkWrap: true,
          itemCount: favorites.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int i) =>
              _row(context, favorites[i]),
        );
      },
    );
  }

  Widget _hint(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Favorite favorite) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(favorite.name),
      subtitle: Text('${favorite.items.length}개 품목'),
      onTap: () => _load(context, favorite),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: '삭제',
        onPressed: () => _remove(context, favorite.id),
      ),
    );
  }

  /// 즐겨찾기 항목을 장바구니로 불러온다. 기존 담긴 목록은 비우고 새로 채운다.
  void _load(BuildContext context, Favorite favorite) {
    Cart.clear();
    for (final FavoriteItem item in favorite.items) {
      Cart.setQty(item.productId, item.qty);
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${favorite.name}"을(를) 불러왔습니다')),
    );
  }

  Future<void> _remove(BuildContext context, String favId) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await FavoriteService.remove(favId);
    } on Exception {
      messenger.showSnackBar(
        const SnackBar(content: Text('삭제하지 못했습니다. 잠시 후 다시 시도해주세요.')),
      );
    }
  }

  /// 이름 입력 다이얼로그를 띄운 뒤 즐겨찾기를 저장한다.
  Future<void> _promptSave(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String? name = await _askName(context);
    if (name == null) return;
    try {
      await FavoriteService.save(
        partnerId: partnerId,
        name: name,
        qtys: Cart.items.value,
        products: products,
      );
      messenger.showSnackBar(const SnackBar(content: Text('즐겨찾기에 저장했습니다')));
    } on FavoriteException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// 즐겨찾기 이름을 입력받는다. 취소하거나 빈 값이면 null을 돌려준다.
  Future<String?> _askName(BuildContext context) {
    final TextEditingController ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('즐겨찾기 저장'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '이름', hintText: '예: 매주 정기발주'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final String v = ctrl.text.trim();
              Navigator.pop(context, v.isEmpty ? null : v);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }
}
