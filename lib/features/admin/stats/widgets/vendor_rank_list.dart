import 'package:flutter/material.dart';
import '../../../../core/utils/format.dart';

class VendorRankList extends StatelessWidget {
  final Map<String, int> partnerAmount;

  const VendorRankList({super.key, required this.partnerAmount});

  @override
  Widget build(BuildContext context) {
    final sortedKeys = partnerAmount.keys.toList()
      ..sort((a, b) => partnerAmount[b]!.compareTo(partnerAmount[a]!));
    
    final topKeys = sortedKeys.take(10).toList();

    if (topKeys.isEmpty) {
      return const Center(child: Text('데이터가 없습니다'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text('거래처별 발주액 순위 (Top 10)', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: topKeys.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final name = topKeys[index];
            final amount = partnerAmount[name]!;
            return ListTile(
              leading: CircleAvatar(
                radius: 12,
                backgroundColor: index < 3 ? Colors.orange : Colors.grey[300],
                child: Text('${index + 1}', style: const TextStyle(fontSize: 12, color: Colors.white)),
              ),
              title: Text(name, style: const TextStyle(fontSize: 14)),
              trailing: Text(formatWon(amount), style: const TextStyle(fontWeight: FontWeight.w500)),
            );
          },
        ),
      ],
    );
  }
}
