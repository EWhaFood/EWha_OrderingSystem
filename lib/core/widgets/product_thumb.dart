import 'package:flutter/material.dart';

/// 상품 썸네일. imageUrl이 있으면 이미지를, 없거나 로드 실패하면 기본 아이콘을 보여준다.
/// 카페24 동기화 상품은 imageUrl이 이미 들어와 있어 그대로 표시된다. (EWOS-44 후속)
class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, required this.imageUrl, this.size = 44});

  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Widget placeholder = Container(
      width: size,
      height: size,
      color: const Color(0xFFF0EFEA),
      child:
          const Icon(Icons.image_outlined, size: 20, color: Color(0xFFB8B6AE)),
    );
    final Widget child = (imageUrl == null || imageUrl!.isEmpty)
        ? placeholder
        : Image.network(
            imageUrl!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                placeholder,
          );
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: child);
  }
}
