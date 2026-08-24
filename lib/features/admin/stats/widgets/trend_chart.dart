import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TrendChart extends StatelessWidget {
  final Map<String, int> dailyAmount;
  final Map<String, int> dailyCount;
  final List<String> days;

  const TrendChart({
    super.key,
    required this.dailyAmount,
    required this.dailyCount,
    required this.days,
  });

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('데이터가 없습니다')),
      );
    }

    return Column(
      children: [
        const Text('일별 발주 금액 추이', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: _getMaxY(),
              barTouchData: BarTouchData(enabled: true),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      int index = value.toInt();
                      if (index < 0 || index >= days.length) return const Text('');
                      if (days.length > 7 && index % (days.length ~/ 5 + 1) != 0) return const Text('');
                      final date = DateTime.parse(days[index]);
                      return Text('${date.month}/${date.day}', style: const TextStyle(fontSize: 10));
                    },
                    reservedSize: 22,
                  ),
                ),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(days.length, (index) {
                final amount = dailyAmount[days[index]] ?? 0;
                return BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: amount.toDouble(),
                      color: Theme.of(context).colorScheme.primary,
                      width: 12,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  double _getMaxY() {
    double max = 0;
    for (var amount in dailyAmount.values) {
      if (amount > max) max = amount.toDouble();
    }
    return max == 0 ? 100 : max * 1.2;
  }
}
