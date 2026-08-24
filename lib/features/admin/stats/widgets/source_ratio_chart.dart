import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class SourceRatioChart extends StatelessWidget {
  final Map<String, int> sourceCount;

  const SourceRatioChart({super.key, required this.sourceCount});

  @override
  Widget build(BuildContext context) {
    final int app = sourceCount['app'] ?? 0;
    final int cafe24 = sourceCount['cafe24'] ?? 0;
    final int total = app + cafe24;

    if (total == 0) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const Text('발주 출처 비중', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SizedBox(
          height: 150,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 30,
              sections: [
                PieChartSectionData(
                  color: Colors.blue,
                  value: app.toDouble(),
                  title: '앱\n${(app/total*100).toStringAsFixed(1)}%',
                  radius: 50,
                  titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                PieChartSectionData(
                  color: Colors.green,
                  value: cafe24.toDouble(),
                  title: '카페24\n${(cafe24/total*100).toStringAsFixed(1)}%',
                  radius: 50,
                  titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
