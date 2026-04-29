import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../services/analytics_service.dart';

const _orange = Color(0xFFFF8C00);
const _purple = Color(0xFF7C3AED);

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final AnalyticsService _analyticsService = AnalyticsService();
  late Future<AnalyticsDto?> _analyticsFuture;

  @override
  void initState() {
    super.initState();
    _analyticsFuture = _analyticsService.getMyAnalytics();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        title: const Text('Аналитика', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: FutureBuilder<AnalyticsDto?>(
        future: _analyticsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _orange));
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const Center(
              child: Text('Не удалось загрузить аналитику',
                  style: TextStyle(color: Colors.grey)),
            );
          }

          final data = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('За последние 30 дней',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 12),
                _buildSummaryGrid(data),
                const SizedBox(height: 28),
                const Text(
                  'Динамика по дням',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildLegend(),
                const SizedBox(height: 12),
                _buildChart(data),
              ],
            ),
          );
        },
      ),
    );
  }

  // 2×2 сетка карточек
  Widget _buildSummaryGrid(AnalyticsDto data) {
    return Column(
      children: [
        Row(
          children: [
            _buildCard('Просмотры', data.totalViewsLast30Days.toString(),
                Icons.visibility_outlined, _orange),
            const SizedBox(width: 12),
            _buildCard('Лайки', data.totalFavoritesLast30Days.toString(),
                Icons.favorite_outline, _purple),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildCard('Заявки', data.totalApplications.toString(),
                Icons.assignment_outlined, Colors.teal),
            const SizedBox(width: 12),
            _buildCard('Написали', data.totalUniqueMessengers.toString(),
                Icons.chat_bubble_outline, Colors.indigo),
          ],
        ),
      ],
    );
  }

  Widget _buildCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.05),
              offset: const Offset(0, 4),
              blurRadius: 10,
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  Text(title,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      children: [
        _legendDot(_orange, 'Просмотры'),
        const SizedBox(width: 16),
        _legendDot(_purple, 'Лайки'),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildChart(AnalyticsDto data) {
    // Объединяем все даты из обоих источников
    final allDates = <String>{
      ...data.viewsByDate.keys,
      ...data.favoritesByDate.keys,
    }.toList()
      ..sort();

    if (allDates.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: const Text('Нет данных для графика',
            style: TextStyle(color: Colors.grey)),
      );
    }

    final viewSpots = <FlSpot>[];
    final favoriteSpots = <FlSpot>[];

    for (int i = 0; i < allDates.length; i++) {
      final date = allDates[i];
      viewSpots.add(FlSpot(i.toDouble(),
          (data.viewsByDate[date] ?? 0).toDouble()));
      favoriteSpots.add(FlSpot(i.toDouble(),
          (data.favoritesByDate[date] ?? 0).toDouble()));
    }

    // Показываем подписи только каждые N дней, чтобы не перекрывались
    final step = allDates.length > 14 ? 3 : (allDates.length > 7 ? 2 : 1);

    return Container(
      height: 260,
      padding: const EdgeInsets.only(right: 16, top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
            offset: const Offset(0, 4),
            blurRadius: 10,
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) => FlLine(
                color: Colors.grey[100]!,
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    if (value == meta.max || value == meta.min) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(value.toInt().toString(),
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey)),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 ||
                        idx >= allDates.length ||
                        idx % step != 0) {
                      return SideTitleWidget(
                          meta: meta, child: const SizedBox.shrink());
                    }
                    final day = allDates[idx].split('-').last;
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(day,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey)),
                    );
                  },
                ),
              ),
              rightTitles:
                  AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((s) {
                    final color = s.barIndex == 0 ? _orange : _purple;
                    final label = s.barIndex == 0 ? 'просм.' : 'лайков';
                    return LineTooltipItem(
                      '${s.y.toInt()} $label',
                      TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    );
                  }).toList();
                },
              ),
            ),
            lineBarsData: [
              // Линия просмотров
              LineChartBarData(
                spots: viewSpots,
                isCurved: true,
                color: _orange,
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                    radius: 3,
                    color: Colors.white,
                    strokeWidth: 2,
                    strokeColor: _orange,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: _orange.withValues(alpha:0.08),
                ),
              ),
              // Линия лайков
              LineChartBarData(
                spots: favoriteSpots,
                isCurved: true,
                color: _purple,
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                    radius: 3,
                    color: Colors.white,
                    strokeWidth: 2,
                    strokeColor: _purple,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: _purple.withValues(alpha:0.06),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
