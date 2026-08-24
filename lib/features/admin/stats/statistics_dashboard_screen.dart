import 'package:flutter/material.dart';
import '../../../core/utils/format.dart';
import 'stats_service.dart';
import 'widgets/trend_chart.dart';
import 'widgets/vendor_rank_list.dart';
import 'widgets/item_aggregate_list.dart';
import 'widgets/source_ratio_chart.dart';

class StatisticsDashboardScreen extends StatefulWidget {
  const StatisticsDashboardScreen({super.key, required this.uid});

  final String uid;

  @override
  State<StatisticsDashboardScreen> createState() => _StatisticsDashboardScreenState();
}

class _StatisticsDashboardScreenState extends State<StatisticsDashboardScreen> {
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 6)),
    end: DateTime.now(),
  );

  bool _isLoading = false;
  StatsSummary? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final stats = await StatsService.getStats(_dateRange);
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading stats: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('통계 대시보드'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildDateSelector(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _stats == null
                    ? const Center(child: Text('데이터를 불러오지 못했습니다'))
                    : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final days = _stats!.dailyAmount.keys.toList()..sort();
    
    return RefreshIndicator(
      onRefresh: _loadStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            _buildSummaryRow(),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TrendChart(
                dailyAmount: _stats!.dailyAmount,
                dailyCount: _stats!.dailyCount,
                days: days,
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: SourceRatioChart(sourceCount: _stats!.sourceCount),
            ),
            const Divider(),
            VendorRankList(partnerAmount: _stats!.partnerAmount),
            const Divider(),
            ItemAggregateList(itemQty: _stats!.itemQty),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          _summaryItem('총 발주액', formatWon(_stats!.totalAmount)),
          _summaryItem('총 건수', '${_stats!.totalCount}건'),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _selectDateRange,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(
                '${formatDate(_dateRange.start)} - ${formatDate(_dateRange.end)}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _quickFilterChip('이번 주', 7),
          const SizedBox(width: 4),
          _quickFilterChip('이번 달', 30),
        ],
      ),
    );
  }

  Widget _quickFilterChip(String label, int days) {
    // 현재 선택된 범위가 7일 또는 30일인지 확인
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = _dateRange.end.difference(_dateRange.start).inDays + 1;
    final bool isSelected = diff == days && 
        _dateRange.end.year == today.year && 
        _dateRange.end.month == today.month && 
        _dateRange.end.day == today.day;

    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _dateRange = DateTimeRange(
              start: today.subtract(Duration(days: days - 1)),
              end: today,
            );
          });
          _loadStats();
        }
      },
    );
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _dateRange,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _loadStats();
    }
  }
}

String formatDate(DateTime date) {
  return '${date.year}.${date.month}.${date.day}';
}
