import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/web_download_stub.dart' if (dart.library.html) '../../core/web_download_web.dart';
import '../auth/auth_controller.dart';

class _RevenueHistoryPoint {
  const _RevenueHistoryPoint({required this.month, required this.revenue});

  final String month;
  final num revenue;
}

class _RevenuePrediction {
  const _RevenuePrediction({
    required this.history,
    required this.predictedMonth,
    required this.predictedRevenue,
    required this.delta,
    required this.deltaPct,
    required this.method,
  });

  final List<_RevenueHistoryPoint> history;
  final String predictedMonth;
  final num predictedRevenue;
  final num delta;
  final num deltaPct;
  final String method;
}

final revenuePredictionProvider = FutureProvider.autoDispose<_RevenuePrediction>((ref) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) throw ApiException('unauthorized');
  final api = ref.read(apiClientProvider);
  final res = await api.getJson('/reports/revenue-prediction', token: token);

  num parseNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  final historyRaw = (res['history'] as List<dynamic>? ?? []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  final history = historyRaw
      .map(
        (e) => _RevenueHistoryPoint(
          month: e['month']?.toString() ?? '',
          revenue: parseNum(e['revenue']),
        ),
      )
      .where((p) => p.month.trim().isNotEmpty)
      .toList();

  final prediction = (res['prediction'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
  final basis = (res['basis'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

  return _RevenuePrediction(
    history: history,
    predictedMonth: prediction['month']?.toString() ?? '',
    predictedRevenue: parseNum(prediction['revenue']),
    delta: parseNum(prediction['delta']),
    deltaPct: parseNum(prediction['deltaPct']),
    method: basis['method']?.toString() ?? 'prediction',
  );
});

class _ProfitPoint {
  const _ProfitPoint({required this.date, required this.revenue, required this.expense});

  final String date;
  final num revenue;
  final num expense;

  num get profit => revenue - expense;
}

class _ProfitSeries {
  const _ProfitSeries({
    required this.month,
    required this.start,
    required this.end,
    required this.totalRevenue,
    required this.totalExpense,
    required this.totalProfit,
    required this.marginPct,
    required this.items,
  });

  final String month;
  final String start;
  final String end;
  final num totalRevenue;
  final num totalExpense;
  final num totalProfit;
  final num marginPct;
  final List<_ProfitPoint> items;
}

final profitSeriesProvider = FutureProvider.autoDispose.family<_ProfitSeries, String>((ref, month) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) throw ApiException('unauthorized');
  final api = ref.read(apiClientProvider);
  final res = await api.getJson('/reports/profit-series', token: token, query: {'month': month});

  num parseNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  final totals = (res['totals'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
  final raw = (res['items'] as List<dynamic>? ?? []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  final items = raw
      .map(
        (e) => _ProfitPoint(
          date: e['date']?.toString() ?? '',
          revenue: parseNum(e['revenue']),
          expense: parseNum(e['expense']),
        ),
      )
      .where((p) => p.date.trim().isNotEmpty)
      .toList();

  return _ProfitSeries(
    month: res['month']?.toString() ?? month,
    start: res['start']?.toString() ?? '',
    end: res['end']?.toString() ?? '',
    totalRevenue: parseNum(totals['revenue']),
    totalExpense: parseNum(totals['expense']),
    totalProfit: parseNum(totals['profit']),
    marginPct: parseNum(totals['marginPct']),
    items: items,
  );
});

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime _monthRef = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _attendanceDate = DateTime.now();
  String _typeFilter = 'all';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthLabel = DateFormat('yyyy-MM').format(_monthRef);
    final dateLabel = DateFormat('yyyy-MM-dd').format(_attendanceDate);
    final q = _searchCtrl.text.trim().toLowerCase();
    final profitAsync = ref.watch(profitSeriesProvider(monthLabel));
    final predictionAsync = ref.watch(revenuePredictionProvider);
    Widget metricCard({
      required String title,
      required String value,
      required String subtitle,
      required IconData icon,
    }) {
      return SizedBox(
        width: 260,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: Text('Reports', style: theme.textTheme.headlineSmall)),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            metricCard(
              title: 'Total Reports',
              value: '4',
              subtitle: 'PDF exports',
              icon: Icons.picture_as_pdf_outlined,
            ),
            metricCard(
              title: 'Monthly Revenue',
              value: monthLabel,
              subtitle: 'Selected month',
              icon: Icons.trending_up,
            ),
            metricCard(
              title: 'Daily Attendance',
              value: dateLabel,
              subtitle: 'Selected date',
              icon: Icons.how_to_reg,
            ),
            metricCard(
              title: 'Quick Export',
              value: 'Ready',
              subtitle: 'One-click PDFs',
              icon: Icons.timelapse_outlined,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Revenue Prediction (Next Month)',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: () => ref.invalidate(revenuePredictionProvider),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                predictionAsync.when(
                  data: (p) {
                    final number = NumberFormat.decimalPattern();
                    final gold = theme.colorScheme.primary;
                    final neon = theme.colorScheme.tertiary;
                    final predictedUp = p.delta >= 0;
                    final deltaColor = predictedUp ? theme.colorScheme.tertiary : theme.colorScheme.error;
                    final history = p.history;
                    final values = <double>[
                      for (final h in history) h.revenue.toDouble(),
                      p.predictedRevenue.toDouble(),
                    ];
                    final maxV = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
                    final maxY = maxV <= 0 ? 1.0 : maxV;
                    final spots = <FlSpot>[
                      for (var i = 0; i < history.length; i += 1) FlSpot(i.toDouble(), history[i].revenue.toDouble()),
                      FlSpot(history.length.toDouble(), p.predictedRevenue.toDouble()),
                    ];
                    final lastIdx = history.length - 1;
                    final predictedSegment = history.isEmpty
                        ? const <FlSpot>[]
                        : [
                            FlSpot(lastIdx.toDouble(), history.last.revenue.toDouble()),
                            FlSpot(history.length.toDouble(), p.predictedRevenue.toDouble()),
                          ];
                    String shortMonth(String ym) => ym.length >= 7 ? ym.substring(5, 7) : ym;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _MetricPill(
                              label: 'Expected',
                              value: number.format(p.predictedRevenue),
                              color: neon,
                            ),
                            _MetricPill(
                              label: 'Change',
                              value: '${predictedUp ? '+' : ''}${number.format(p.delta)} (${predictedUp ? '+' : ''}${p.deltaPct.toStringAsFixed(2)}%)',
                              color: deltaColor,
                            ),
                            Text(
                              'Based on last 3 months • ${p.method.replaceAll('_', ' ')}',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          height: 260,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
                                theme.colorScheme.surface.withValues(alpha: 0.72),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: neon.withValues(alpha: 0.14),
                                blurRadius: 26,
                                offset: const Offset(0, 16),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.fromLTRB(12, 12, 16, 10),
                          child: LineChart(
                            LineChartData(
                              minY: 0,
                              maxY: maxY * 1.12,
                              gridData: FlGridData(
                                show: true,
                                horizontalInterval: maxY / 4,
                                getDrawingHorizontalLine: (v) => FlLine(
                                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
                                  strokeWidth: 1,
                                ),
                                drawVerticalLine: false,
                              ),
                              borderData: FlBorderData(show: false),
                              titlesData: FlTitlesData(
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 44,
                                    interval: maxY / 3,
                                    getTitlesWidget: (value, meta) {
                                      return Text(
                                        number.format(value),
                                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                      );
                                    },
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    interval: 1,
                                    getTitlesWidget: (value, meta) {
                                      final i = value.round();
                                      if (i < 0) return const SizedBox.shrink();
                                      if (i == history.length) {
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Text(
                                            p.predictedMonth.isEmpty ? 'Next' : shortMonth(p.predictedMonth),
                                            style: theme.textTheme.labelSmall?.copyWith(color: neon),
                                          ),
                                        );
                                      }
                                      if (i >= history.length) return const SizedBox.shrink();
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          shortMonth(history[i].month),
                                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              lineTouchData: LineTouchData(
                                enabled: true,
                                touchTooltipData: LineTouchTooltipData(
                                  getTooltipColor: (touchedSpot) => theme.colorScheme.surfaceContainerHighest,
                                  tooltipBorder: BorderSide(color: theme.colorScheme.outlineVariant),
                                  getTooltipItems: (touchedSpots) {
                                    return touchedSpots.map((s) {
                                      final idx = s.x.round();
                                      final label = idx < history.length ? history[idx].month : (p.predictedMonth.isEmpty ? 'Next' : p.predictedMonth);
                                      return LineTooltipItem(
                                        '$label\n${number.format(s.y)}',
                                        theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurface) ?? const TextStyle(),
                                      );
                                    }).toList();
                                  },
                                ),
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: spots,
                                  isCurved: true,
                                  curveSmoothness: 0.22,
                                  color: gold.withValues(alpha: 0.22),
                                  barWidth: 10,
                                  dotData: const FlDotData(show: false),
                                ),
                                LineChartBarData(
                                  spots: spots,
                                  isCurved: true,
                                  curveSmoothness: 0.22,
                                  color: gold,
                                  barWidth: 2.8,
                                  dotData: FlDotData(
                                    show: true,
                                    checkToShowDot: (spot, barData) => spot.x >= history.length - 0.5,
                                    getDotPainter: (spot, percent, barData, idx) {
                                      final isPred = spot.x.round() == history.length;
                                      final c = isPred ? neon : gold;
                                      return FlDotCirclePainter(
                                        radius: isPred ? 4.8 : 3.6,
                                        color: c,
                                        strokeWidth: 2,
                                        strokeColor: theme.colorScheme.surface,
                                      );
                                    },
                                  ),
                                ),
                                if (predictedSegment.isNotEmpty) ...[
                                  LineChartBarData(
                                    spots: predictedSegment,
                                    isCurved: false,
                                    color: neon.withValues(alpha: 0.22),
                                    barWidth: 10,
                                    dotData: const FlDotData(show: false),
                                  ),
                                  LineChartBarData(
                                    spots: predictedSegment,
                                    isCurved: false,
                                    color: neon,
                                    barWidth: 2.8,
                                    dotData: const FlDotData(show: false),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(e.toString(), style: theme.textTheme.bodySmall),
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Expense vs Revenue (Profit Margin)',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _pickMonth(context),
                      icon: const Icon(Icons.date_range),
                      label: Text(monthLabel),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: () => ref.invalidate(profitSeriesProvider(monthLabel)),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                profitAsync.when(
                  data: (s) {
                    final number = NumberFormat.decimalPattern();
                    final profitColor = s.totalProfit >= 0 ? theme.colorScheme.tertiary : theme.colorScheme.error;
                    final last = s.items.isNotEmpty ? s.items.last : null;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _MetricPill(
                              label: 'Revenue',
                              value: number.format(s.totalRevenue),
                              color: theme.colorScheme.primary,
                            ),
                            _MetricPill(
                              label: 'Expense',
                              value: number.format(s.totalExpense),
                              color: theme.colorScheme.error,
                            ),
                            _MetricPill(
                              label: 'Profit',
                              value: number.format(s.totalProfit),
                              color: profitColor,
                            ),
                            _MetricPill(
                              label: 'Margin',
                              value: '${s.marginPct.toStringAsFixed(2)}%',
                              color: profitColor,
                            ),
                            if (last != null)
                              Text(
                                'Month end gap: ${number.format(last.profit)}',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 220,
                          width: double.infinity,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: theme.colorScheme.outlineVariant),
                              color: theme.colorScheme.surface,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: CustomPaint(
                                painter: _ProfitAreaPainter(
                                  items: s.items,
                                  revenueColor: theme.colorScheme.primary,
                                  expenseColor: theme.colorScheme.error,
                                  areaColor: profitColor,
                                  gridColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(e.toString(), style: theme.textTheme.bodySmall),
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(_typeFilter),
                    initialValue: _typeFilter,
                    decoration: const InputDecoration(labelText: 'Report type'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Reports')),
                      DropdownMenuItem(value: 'export', child: Text('Full Export')),
                      DropdownMenuItem(value: 'monthly', child: Text('Monthly Revenue')),
                      DropdownMenuItem(value: 'expired', child: Text('Expired Members')),
                      DropdownMenuItem(value: 'daily', child: Text('Daily Attendance')),
                    ],
                    onChanged: (v) => setState(() => _typeFilter = v ?? 'all'),
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Search report',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                OutlinedButton(
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _typeFilter = 'all');
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Builder(
          builder: (context) {
            final defs = <({String type, String title, String subtitle, IconData icon, Widget trailing})>[
              (
                type: 'export',
                title: 'Full Reports Export',
                subtitle: 'PDF • Obsidian & Gold premium export for $monthLabel',
                icon: Icons.picture_as_pdf_outlined,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickMonth(context),
                      icon: const Icon(Icons.date_range),
                      label: Text(monthLabel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _openPdfActions(
                        context,
                        title: 'Full Reports Export',
                        path: '/pdf/reports.pdf',
                        fileName: 'reports_$monthLabel.pdf',
                        query: {'month': monthLabel},
                      ),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF'),
                    ),
                  ],
                ),
              ),
              (
                type: 'monthly',
                title: 'Monthly Revenue Report',
                subtitle: 'PDF • Paid invoices summary for $monthLabel',
                icon: Icons.trending_up,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickMonth(context),
                      icon: const Icon(Icons.date_range),
                      label: Text(monthLabel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _openPdfActions(
                        context,
                        title: 'Monthly Revenue Report',
                        path: '/reports/monthly-revenue.pdf',
                        fileName: 'monthly_revenue_$monthLabel.pdf',
                        query: {'month': monthLabel},
                      ),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF'),
                    ),
                  ],
                ),
              ),
              (
                type: 'expired',
                title: 'Expired Members List',
                subtitle: 'PDF • All members whose latest membership is expired',
                icon: Icons.person_off,
                trailing: FilledButton.icon(
                  onPressed: () => _openPdfActions(
                    context,
                    title: 'Expired Members List',
                    path: '/reports/expired-members.pdf',
                    fileName: 'expired_members_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf',
                  ),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF'),
                ),
              ),
              (
                type: 'daily',
                title: 'Daily Attendance Log',
                subtitle: 'PDF • Attendance for $dateLabel',
                icon: Icons.how_to_reg,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickDate(context),
                      icon: const Icon(Icons.event),
                      label: Text(dateLabel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _openPdfActions(
                        context,
                        title: 'Daily Attendance Log',
                        path: '/reports/daily-attendance.pdf',
                        fileName: 'attendance_$dateLabel.pdf',
                        query: {'date': dateLabel},
                      ),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF'),
                    ),
                  ],
                ),
              ),
            ];

            final visible = defs.where((d) {
              if (_typeFilter != 'all' && d.type != _typeFilter) return false;
              if (q.isNotEmpty) {
                final hay = '${d.title} ${d.subtitle}'.toLowerCase();
                if (!hay.contains(q)) return false;
              }
              return true;
            }).toList();

            if (visible.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(child: Text('No results', style: theme.textTheme.bodySmall)),
              );
            }

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final d in visible)
                  _ReportTile(
                    title: d.title,
                    subtitle: d.subtitle,
                    icon: d.icon,
                    trailing: d.trailing,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _pickMonth(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _monthRef,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Pick any day in the month',
    );
    if (picked == null) return;
    setState(() => _monthRef = DateTime(picked.year, picked.month, 1));
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _attendanceDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() => _attendanceDate = picked);
  }

  Future<void> _openPdfActions(
    BuildContext context, {
    required String title,
    required String path,
    required String fileName,
    Map<String, String>? query,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: const Text('Preview ya download?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runPdf(context, preview: true, path: path, fileName: fileName, query: query);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runPdf(context, preview: false, path: path, fileName: fileName, query: query);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runPdf(
    BuildContext context, {
    required bool preview,
    required String path,
    required String fileName,
    Map<String, String>? query,
  }) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final bytes = await api.getBytes(path, token: token, query: query);
      final savedPath = preview
          ? previewBytes(fileName: fileName, bytes: bytes, mimeType: 'application/pdf')
          : downloadBytes(fileName: fileName, bytes: bytes, mimeType: 'application/pdf');
      if (!context.mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved: $savedPath')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(preview ? 'Opening PDF…' : 'Download started')));
      }
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF download failed')));
    }
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 10,
            width: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text('$label: ', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(value, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ProfitAreaPainter extends CustomPainter {
  _ProfitAreaPainter({
    required this.items,
    required this.revenueColor,
    required this.expenseColor,
    required this.areaColor,
    required this.gridColor,
  });

  final List<_ProfitPoint> items;
  final Color revenueColor;
  final Color expenseColor;
  final Color areaColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (items.length < 2) return;

    final maxV = items
        .map((p) => [p.revenue.toDouble(), p.expense.toDouble()].reduce((a, b) => a > b ? a : b))
        .reduce((a, b) => a > b ? a : b);
    final maxY = maxV <= 0 ? 1.0 : maxV;

    final rect = Offset.zero & size;
    final plot = Rect.fromLTWH(rect.left, rect.top + 6, rect.width, rect.height - 12);

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final t in [0.25, 0.5, 0.75]) {
      final y = plot.bottom - plot.height * t;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }

    Offset point(int i, double v) {
      final x = plot.left + (plot.width * i / (items.length - 1));
      final y = plot.bottom - (plot.height * (v / maxY));
      return Offset(x, y);
    }

    final revenuePts = <Offset>[];
    final expensePts = <Offset>[];
    for (var i = 0; i < items.length; i += 1) {
      revenuePts.add(point(i, items[i].revenue.toDouble()));
      expensePts.add(point(i, items[i].expense.toDouble()));
    }

    final areaPath = Path()..moveTo(revenuePts.first.dx, revenuePts.first.dy);
    for (var i = 1; i < revenuePts.length; i += 1) {
      areaPath.lineTo(revenuePts[i].dx, revenuePts[i].dy);
    }
    for (var i = expensePts.length - 1; i >= 0; i -= 1) {
      areaPath.lineTo(expensePts[i].dx, expensePts[i].dy);
    }
    areaPath.close();

    final fillPaint = Paint()
      ..color = areaColor.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    canvas.drawPath(areaPath, fillPaint);

    final revenuePaint = Paint()
      ..color = revenueColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final expensePaint = Paint()
      ..color = expenseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Path linePath(List<Offset> pts) {
      final p = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i += 1) {
        p.lineTo(pts[i].dx, pts[i].dy);
      }
      return p;
    }

    canvas.drawPath(linePath(revenuePts), revenuePaint);
    canvas.drawPath(linePath(expensePts), expensePaint);

    final lastRevenue = revenuePts.last;
    final lastExpense = expensePts.last;
    final gapPaint = Paint()
      ..color = areaColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(lastRevenue, lastExpense, gapPaint);

    final dotPaintRevenue = Paint()..color = revenueColor;
    final dotPaintExpense = Paint()..color = expenseColor;
    canvas.drawCircle(lastRevenue, 4.5, dotPaintRevenue);
    canvas.drawCircle(lastExpense, 4.5, dotPaintExpense);
  }

  @override
  bool shouldRepaint(covariant _ProfitAreaPainter oldDelegate) {
    if (oldDelegate.items.length != items.length) return true;
    if (oldDelegate.revenueColor != revenueColor) return true;
    if (oldDelegate.expenseColor != expenseColor) return true;
    if (oldDelegate.areaColor != areaColor) return true;
    if (oldDelegate.gridColor != gridColor) return true;
    for (var i = 0; i < items.length; i += 1) {
      final a = items[i];
      final b = oldDelegate.items[i];
      if (a.date != b.date) return true;
      if (a.revenue != b.revenue) return true;
      if (a.expense != b.expense) return true;
    }
    return false;
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 520,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
