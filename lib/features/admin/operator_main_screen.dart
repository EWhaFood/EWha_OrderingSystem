import 'package:flutter/material.dart';
import '../orders/operator_order_list_screen.dart';
import 'stats/statistics_dashboard_screen.dart';

class OperatorMainScreen extends StatefulWidget {
  const OperatorMainScreen({super.key, required this.uid});

  final String uid;

  @override
  State<OperatorMainScreen> createState() => _OperatorMainScreenState();
}

class _OperatorMainScreenState extends State<OperatorMainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          OperatorOrderListScreen(uid: widget.uid),
          StatisticsDashboardScreen(uid: widget.uid),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: '발주 현황',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: '통계',
          ),
        ],
      ),
    );
  }
}
