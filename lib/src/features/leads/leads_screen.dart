import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
 
import '../../core/api_client.dart';
import '../../core/form_dialog.dart';
import '../../core/providers.dart';
import '../../core/web_download_stub.dart' if (dart.library.html) '../../core/web_download_web.dart';
import '../../models/models.dart';
import '../auth/auth_controller.dart';
 
final leadsQueryProvider = StateProvider.autoDispose<_LeadsQuery>((ref) {
  return const _LeadsQuery(q: '', status: 'all');
});
 
final leadsControllerProvider = StateNotifierProvider.autoDispose<_LeadsController, AsyncValue<List<Lead>>>((ref) {
  return _LeadsController(ref)..load();
});
 
class _LeadsQuery {
  const _LeadsQuery({required this.q, required this.status});
 
  final String q;
  final String status;
 
  Map<String, String> toQuery() {
    final map = <String, String>{'limit': '200'};
    if (q.trim().isNotEmpty) map['q'] = q.trim();
    if (status != 'all') map['status'] = status;
    return map;
  }
 
  _LeadsQuery copyWith({String? q, String? status}) {
    return _LeadsQuery(q: q ?? this.q, status: status ?? this.status);
  }
}
 
class _LeadsController extends StateNotifier<AsyncValue<List<Lead>>> {
  _LeadsController(this.ref) : super(const AsyncValue.loading());
 
  final Ref ref;
 
  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final q = ref.read(leadsQueryProvider);
      final res = await api.getJson('/leads', token: token, query: q.toQuery());
      final items = (res['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Lead.fromJson(e.cast<String, dynamic>()))
          .toList();
      state = AsyncValue.data(items);
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error('leads_load_failed', st);
    }
  }
 
  Future<void> addLead({
    required String fullName,
    String? phone,
    String? source,
    String? interest,
    String? nextContactDate,
    required String status,
    String? notes,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.postJson('/leads', token: token, body: {
      'fullName': fullName.trim(),
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'source': source?.trim().isEmpty == true ? null : source?.trim(),
      'interest': interest?.trim().isEmpty == true ? null : interest?.trim(),
      'nextContactDate': nextContactDate?.trim().isEmpty == true ? null : nextContactDate?.trim(),
      'status': status,
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
    });
    await load();
  }
 
  Future<void> updateLead({
    required int id,
    required String fullName,
    String? phone,
    String? source,
    String? interest,
    String? nextContactDate,
    required String status,
    String? notes,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.patchJson('/leads/$id', token: token, body: {
      'fullName': fullName.trim(),
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'source': source?.trim().isEmpty == true ? null : source?.trim(),
      'interest': interest?.trim().isEmpty == true ? null : interest?.trim(),
      'nextContactDate': nextContactDate?.trim().isEmpty == true ? null : nextContactDate?.trim(),
      'status': status,
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
    });
    await load();
  }
 
  Future<void> deleteLead(int id) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.deleteJson('/leads/$id', token: token);
    await load();
  }
}
 
class LeadsScreen extends ConsumerWidget {
  const LeadsScreen({super.key});
 
  Color _statusColor(String status) {
    switch (status) {
      case 'trial':
        return const Color(0xFF2563EB);
      case 'lost':
        return const Color(0xFFDC2626);
      case 'converted':
        return const Color(0xFF0F766E);
      default:
        return const Color(0xFFD4AF37);
    }
  }

  Widget _statusBadge(BuildContext context, String status) {
    final theme = Theme.of(context);
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: c.withAlpha(28),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(status, style: theme.textTheme.labelMedium?.copyWith(color: c)),
    );
  }

  Future<void> _openLeadsPdfActions(BuildContext context, WidgetRef ref) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Leads PDF'),
          content: const Text('Preview ya download?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runLeadsPdf(context, ref, preview: true, today: today);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runLeadsPdf(context, ref, preview: false, today: today);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
            ),
          ],
        );
      },
    );
  }
 
  Future<void> _runLeadsPdf(
    BuildContext context,
    WidgetRef ref, {
    required bool preview,
    required String today,
  }) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final bytes = await api.getBytes('/pdf/leads.pdf', token: token);
      final name = 'leads_$today.pdf';
      final savedPath = preview
          ? previewBytes(fileName: name, bytes: bytes, mimeType: 'application/pdf')
          : downloadBytes(fileName: name, bytes: bytes, mimeType: 'application/pdf');
      if (!context.mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved: $savedPath')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(preview ? 'Opening PDF…' : 'Download started')));
      }
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF failed')));
    }
  }
 
  Future<void> _openLeadForm(BuildContext context, WidgetRef ref, {Lead? lead}) async {
    final isEdit = lead != null;
    final nameCtrl = TextEditingController(text: lead?.fullName ?? '');
    final phoneCtrl = TextEditingController(text: lead?.phone ?? '');
    final sourceCtrl = TextEditingController(text: lead?.source ?? '');
    final interestCtrl = TextEditingController(text: lead?.interest ?? '');
    final notesCtrl = TextEditingController(text: lead?.notes ?? '');
    String status = lead?.status ?? 'new';
    DateTime? nextContact =
        (lead?.nextContactDate != null && lead!.nextContactDate!.trim().isNotEmpty) ? DateTime.tryParse(lead.nextContactDate!) : null;
    final formKey = GlobalKey<FormState>();
    final date = DateFormat('yyyy-MM-dd');
    final pretty = DateFormat('dd MMM yyyy');
 
    await showAppFormDialog<void>(
      context: context,
      icon: Icons.person_add_alt_1,
      title: isEdit ? 'Edit Lead' : 'Add Lead',
      subtitle: 'Potential member / enquiry',
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return Form(
            key: formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Enter name' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: sourceCtrl,
                  decoration: const InputDecoration(labelText: 'Source (Facebook, Walk-in, Referral)'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: interestCtrl,
                  decoration: const InputDecoration(labelText: 'Interest (Weight loss, Strength, etc.)'),
                ),
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final initial = nextContact ?? DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked == null) return;
                    setModalState(() => nextContact = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Next Contact Date'),
                    child: Text(nextContact == null ? '-' : pretty.format(nextContact!)),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'new', child: Text('New')),
                    DropdownMenuItem(value: 'trial', child: Text('Trial')),
                    DropdownMenuItem(value: 'converted', child: Text('Converted')),
                    DropdownMenuItem(value: 'lost', child: Text('Lost')),
                  ],
                  onChanged: (v) => setModalState(() => status = v ?? 'new'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 3,
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            if (!(formKey.currentState?.validate() ?? false)) return;
            final controller = ref.read(leadsControllerProvider.notifier);
            if (isEdit) {
              await controller.updateLead(
                id: lead!.id,
                fullName: nameCtrl.text,
                phone: phoneCtrl.text,
                source: sourceCtrl.text,
                interest: interestCtrl.text,
                nextContactDate: nextContact == null ? null : date.format(nextContact!),
                status: status,
                notes: notesCtrl.text,
              );
            } else {
              await controller.addLead(
                fullName: nameCtrl.text,
                phone: phoneCtrl.text,
                source: sourceCtrl.text,
                interest: interestCtrl.text,
                nextContactDate: nextContact == null ? null : date.format(nextContact!),
                status: status,
                notes: notesCtrl.text,
              );
            }
            if (context.mounted) Navigator.of(context).maybePop();
          },
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    ).whenComplete(() {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      sourceCtrl.dispose();
      interestCtrl.dispose();
      notesCtrl.dispose();
    });
  }
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final q = ref.watch(leadsQueryProvider);
    final async = ref.watch(leadsControllerProvider);
 
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Leads', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  tooltip: 'PDF',
                  onPressed: () => _openLeadsPdfActions(context, ref),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
                FilledButton.icon(
                  onPressed: () => _openLeadForm(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Lead'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search (name / phone / source)',
                    ),
                    onChanged: (v) {
                      ref.read(leadsQueryProvider.notifier).state = q.copyWith(q: v);
                      ref.read(leadsControllerProvider.notifier).load();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    value: q.status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All')),
                      DropdownMenuItem(value: 'new', child: Text('New')),
                      DropdownMenuItem(value: 'trial', child: Text('Trial')),
                      DropdownMenuItem(value: 'converted', child: Text('Converted')),
                      DropdownMenuItem(value: 'lost', child: Text('Lost')),
                    ],
                    onChanged: (v) {
                      ref.read(leadsQueryProvider.notifier).state = q.copyWith(status: v ?? 'all');
                      ref.read(leadsControllerProvider.notifier).load();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => ref.read(leadsControllerProvider.notifier).load(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: async.when(
                data: (items) {
                  if (items.isEmpty) return const Center(child: Text('No leads'));
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                      color: theme.colorScheme.surface,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 44,
                        dataRowMinHeight: 48,
                        dataRowMaxHeight: 56,
                        columnSpacing: 18,
                        horizontalMargin: 16,
                        columns: const [
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Phone')),
                          DataColumn(label: Text('Source')),
                          DataColumn(label: Text('Interest')),
                          DataColumn(label: Text('Next Contact')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: [
                          for (final l in items)
                            DataRow(
                              cells: [
                                DataCell(SizedBox(width: 180, child: Text(l.fullName, overflow: TextOverflow.ellipsis))),
                                DataCell(SizedBox(width: 120, child: Text(l.phone ?? '-', overflow: TextOverflow.ellipsis))),
                                DataCell(SizedBox(width: 140, child: Text(l.source ?? '-', overflow: TextOverflow.ellipsis))),
                                DataCell(SizedBox(width: 160, child: Text(l.interest ?? '-', overflow: TextOverflow.ellipsis))),
                                DataCell(Text(l.nextContactDate == null || l.nextContactDate!.isEmpty ? '-' : l.nextContactDate!)),
                                DataCell(_statusBadge(context, l.status)),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Convert to Member',
                                        onPressed: () {
                                          final uri = Uri(
                                            path: '/members',
                                            queryParameters: {
                                              'prefill': 'lead',
                                              'fullName': l.fullName,
                                              if ((l.phone ?? '').trim().isNotEmpty) 'phone': l.phone!.trim(),
                                            },
                                          );
                                          context.go(uri.toString());
                                        },
                                        icon: const Icon(Icons.person_add_alt_1_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Edit',
                                        onPressed: () => _openLeadForm(context, ref, lead: l),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete',
                                        onPressed: () async {
                                          await showDialog<void>(
                                            context: context,
                                            builder: (context) {
                                              return AlertDialog(
                                                title: const Text('Delete lead?'),
                                                content: Text(l.fullName),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.of(context).pop(),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () async {
                                                      Navigator.of(context).pop();
                                                      await ref.read(leadsControllerProvider.notifier).deleteLead(l.id);
                                                    },
                                                    child: const Text('Delete'),
                                                  ),
                                                ],
                                              );
                                            },
                                          );
                                        },
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(e.toString())),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
