import 'package:flutter/material.dart';

class ItemAggregateList extends StatelessWidget {
  final Map<String, int> itemQty;

  const ItemAggregateList({super.key, required this.itemQty});

  @override
  Widget build(BuildContext context) {
    final sortedKeys = itemQty.keys.toList()
      ..sort((a, b) => itemQty[b]!.compareTo(itemQty[a]!));
    
    final topKeys = sortedKeys.take(15).toList();

    if (topKeys.isEmpty) {
      return const Center(child: Text('데이터가 없습니다'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text('품목별 발주량 집계 (Top 15)', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: topKeys.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final name = topKeys[index];
            final qty = itemQty[name]!;
            return ListTile(
              dense: true,
              title: Text(name),
              trailing: Text('$qty개', style: const TextStyle(fontWeight: FontWeight.w500)),
            );
          },
        ),
      ],
    );
  }
}
