import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../services/analytics_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final AnalyticsService _analyticsService = AnalyticsService();
  late Future<AnalyticsDto> _analyticsFuture;

  @override
  void initState() {
    super.initState();
    _analyticsFuture = _analyticsService.getMyAnalytics();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Аналитика', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: FutureBuilder<AnalyticsDto>(
        future: _analyticsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C00)));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Ошибка загрузки аналитики: ${snapshot.error}'));
          }

          final data = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryCards(data),
                const SizedBox(height: 32),
                const Text(
                  'Просмотры за последние 30 дней',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildChart(data),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCards(AnalyticsDto data) {
    return Row(
      children: [
        _buildCard('Просмотры', data.totalViewsLast30Days.toString(), Icons.visibility),
        const SizedBox(width: 12),
        _buildCard('Заявки', data.totalApplications.toString(), Icons.assignment),
        const SizedBox(width: 12),
        _buildCard('Избранное', data.totalFavorites.toString(), Icons.favorite),
      ],
    );
  }

  Widget _buildCard(String title, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              offset: const Offset(0, 4),
              blurRadius: 10,
            )
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFFF8C00), size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(AnalyticsDto data) {
    if (data.viewsByDate.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: const Text('Нет данных для графика', style: TextStyle(color: Colors.grey)),
      );
    }

    final sortedKeys = data.viewsByDate.keys.toList()..sort();
    final spots = <FlSpot>[];
    
    for (int i = 0; i < sortedKeys.length; i++) {
      spots.add(FlSpot(i.toDouble(), data.viewsByDate[sortedKeys[i]]!.toDouble()));
    }

    return Container(
      height: 250,
      padding: const EdgeInsets.only(right: 16, top: 16),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 30),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() >= 0 && value.toInt() < sortedKeys.length) {
                    final dateStr = sortedKeys[value.toInt()];
                    final day = dateStr.split('-').last;
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(day, style: const TextStyle(fontSize: 10)),
                    );
                  }
                  return SideTitleWidget(meta: meta, child: const Text(''));
                },
              ),
            ),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: const Color(0xFFFF8C00),
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFFFF8C00).withOpacity(0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
