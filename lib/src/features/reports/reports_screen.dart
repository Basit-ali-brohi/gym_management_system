import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/web_download_stub.dart' if (dart.library.html) '../../core/web_download_web.dart';
import '../auth/auth_controller.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime _monthRef = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _attendanceDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthLabel = DateFormat('yyyy-MM').format(_monthRef);
    final dateLabel = DateFormat('yyyy-MM-dd').format(_attendanceDate);
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
              value: '3',
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
              title: 'Avg Lead Time',
              value: '0 days',
              subtitle: 'Production estimate',
              icon: Icons.timelapse_outlined,
            ),
          ],
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
                    initialValue: 'all',
                    decoration: const InputDecoration(labelText: 'Report type'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Reports')),
                      DropdownMenuItem(value: 'monthly', child: Text('Monthly Revenue')),
                      DropdownMenuItem(value: 'expired', child: Text('Expired Members')),
                      DropdownMenuItem(value: 'daily', child: Text('Daily Attendance')),
                    ],
                    onChanged: (_) {},
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search report',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) {},
                  ),
                ),
                OutlinedButton(onPressed: () {}, child: const Text('Clear')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ReportTile(
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
            _ReportTile(
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
            _ReportTile(
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
          ],
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
