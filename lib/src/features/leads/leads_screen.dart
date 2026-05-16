import 'dart:async';

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
    final hadData = state.valueOrNull != null;
    if (!hadData) state = const AsyncValue.loading();
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
      if (!hadData) state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      if (!hadData) state = AsyncValue.error('leads_load_failed', st);
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
 
class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key});

  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _overdueOnly = false;
  bool _sortByNextContact = true;
  String _sourceFilter = 'all';
  String _interestFilter = 'all';
  String _nextContactFilter = 'all';
  bool _hydratedFromRoute = false;

  ({int level, int currentXp, int nextXp, int totalXp}) _computeManagerLevel(int totalConverted) {
    var level = 1;
    var remaining = totalConverted;
    var next = 5;
    while (remaining >= next) {
      remaining -= next;
      level += 1;
      next = 5 + ((level - 1) * 3);
    }
    return (level: level, currentXp: remaining, nextXp: next, totalXp: totalConverted);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case 'trial':
        return const Color(0xFF2563EB);
      case 'lost':
        return const Color(0xFFDC2626);
      case 'converted':
        return const Color(0xFF0F766E);
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Widget _statusBadge(BuildContext context, String status) {
    final theme = Theme.of(context);
    final c = _statusColor(context, status);
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

  Future<void> _openLeadsPdfActions(BuildContext context) async {
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
                await _runLeadsPdf(context, preview: true, today: today);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runLeadsPdf(context, preview: false, today: today);
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
    {required bool preview, required String today}) async {
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
 
  Future<void> _openLeadForm(BuildContext context, {Lead? lead}) async {
    final isEdit = lead != null;
    final nameCtrl = TextEditingController(text: lead?.fullName ?? '');
    final phoneCtrl = TextEditingController(text: lead?.phone ?? '');
    final notesCtrl = TextEditingController(text: lead?.notes ?? '');
    String status = lead?.status ?? 'new';
    final leads = ref.read(leadsControllerProvider).valueOrNull ?? const <Lead>[];
    final commonSources = <String>[
      'Walk-in',
      'Facebook',
      'Instagram',
      'Google',
      'Referral',
      'WhatsApp',
      'Call',
      'Other',
    ];
    final commonInterests = <String>[
      'Weight loss',
      'Strength training',
      'Personal training',
      'Fat loss + cardio',
      'Muscle gain',
      'Fitness',
      'Rehab',
    ];
    final sourceOptions = <String>{
      ...commonSources,
      for (final l in leads)
        if ((l.source ?? '').trim().isNotEmpty) l.source!.trim(),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final interestOptions = <String>{
      ...commonInterests,
      for (final l in leads)
        if ((l.interest ?? '').trim().isNotEmpty) l.interest!.trim(),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    TextEditingController? sourceAutoCtrl;
    TextEditingController? interestAutoCtrl;
    DateTime? nextContact =
        (lead?.nextContactDate != null && lead!.nextContactDate!.trim().isNotEmpty) ? DateTime.tryParse(lead.nextContactDate!) : null;
    if (!isEdit && nextContact == null) {
      final t = DateTime.now();
      nextContact = DateTime(t.year, t.month, t.day).add(const Duration(days: 1));
    }
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
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: lead?.source ?? ''),
                  optionsBuilder: (value) {
                    final q = value.text.trim().toLowerCase();
                    if (q.isEmpty) return sourceOptions.take(8);
                    return sourceOptions.where((o) => o.toLowerCase().contains(q)).take(8);
                  },
                  onSelected: (v) => sourceAutoCtrl?.text = v,
                  fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                    sourceAutoCtrl ??= textEditingController;
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: const InputDecoration(labelText: 'Source', hintText: 'Walk-in, Facebook, Referral...'),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: lead?.interest ?? ''),
                  optionsBuilder: (value) {
                    final q = value.text.trim().toLowerCase();
                    if (q.isEmpty) return interestOptions.take(8);
                    return interestOptions.where((o) => o.toLowerCase().contains(q)).take(8);
                  },
                  onSelected: (v) => interestAutoCtrl?.text = v,
                  fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                    interestAutoCtrl ??= textEditingController;
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: const InputDecoration(labelText: 'Interest', hintText: 'Weight loss, Strength...'),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        final t = DateTime.now();
                        setModalState(() => nextContact = DateTime(t.year, t.month, t.day));
                      },
                      icon: const Icon(Icons.today_outlined),
                      label: const Text('Today'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final t = DateTime.now();
                        setModalState(() => nextContact = DateTime(t.year, t.month, t.day).add(const Duration(days: 1)));
                      },
                      icon: const Icon(Icons.event_outlined),
                      label: const Text('Tomorrow'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final t = DateTime.now();
                        setModalState(() => nextContact = DateTime(t.year, t.month, t.day).add(const Duration(days: 7)));
                      },
                      icon: const Icon(Icons.date_range_outlined),
                      label: const Text('Next week'),
                    ),
                  ],
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
                  initialValue: status,
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
        TextButton(onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            if (!(formKey.currentState?.validate() ?? false)) return;
            final controller = ref.read(leadsControllerProvider.notifier);
            final source = sourceAutoCtrl?.text.trim() ?? '';
            final interest = interestAutoCtrl?.text.trim() ?? '';
            if (isEdit) {
              await controller.updateLead(
                id: lead.id,
                fullName: nameCtrl.text,
                phone: phoneCtrl.text,
                source: source,
                interest: interest,
                nextContactDate: nextContact == null ? null : date.format(nextContact!),
                status: status,
                notes: notesCtrl.text,
              );
            } else {
              await controller.addLead(
                fullName: nameCtrl.text,
                phone: phoneCtrl.text,
                source: source,
                interest: interest,
                nextContactDate: nextContact == null ? null : date.format(nextContact!),
                status: status,
                notes: notesCtrl.text,
              );
            }
            if (context.mounted) Navigator.of(context, rootNavigator: true).maybePop();
          },
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    ).whenComplete(() {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      notesCtrl.dispose();
    });
  }

  bool _isOverdue(Lead l, DateTime today) {
    final raw = l.nextContactDate?.trim();
    if (raw == null || raw.isEmpty) return false;
    final d = DateTime.tryParse(raw);
    if (d == null) return false;
    final dateOnly = DateTime(d.year, d.month, d.day);
    final t = DateTime(today.year, today.month, today.day);
    if (l.status == 'converted' || l.status == 'lost') return false;
    return dateOnly.isBefore(t);
  }

  String _fmtDateOnly(String? raw) {
    final s = raw?.trim();
    if (s == null || s.isEmpty) return '-';
    final m = RegExp(r'^\d{4}-\d{2}-\d{2}').firstMatch(s);
    if (m != null) return m.group(0)!;
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    final y = d.year.toString().padLeft(4, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$mm-$dd';
  }

  Future<void> _openLeadDetails(BuildContext context, Lead l) async {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final overdue = _isOverdue(l, today);
    final pretty = DateFormat('dd MMM yyyy');
    final d = (l.nextContactDate == null || l.nextContactDate!.trim().isEmpty) ? null : DateTime.tryParse(l.nextContactDate!.trim());
    final nextText = d == null ? '-' : pretty.format(d);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Expanded(child: Text(l.fullName)),
              _statusBadge(context, l.status),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _InfoRow(label: 'Phone', value: (l.phone ?? '-').trim().isEmpty ? '-' : l.phone!.trim(), icon: Icons.call_outlined),
                const SizedBox(height: 10),
                _InfoRow(label: 'Source', value: (l.source ?? '-').trim().isEmpty ? '-' : l.source!.trim(), icon: Icons.public_outlined),
                const SizedBox(height: 10),
                _InfoRow(label: 'Interest', value: (l.interest ?? '-').trim().isEmpty ? '-' : l.interest!.trim(), icon: Icons.bolt_outlined),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    color: overdue ? theme.colorScheme.error.withAlpha(14) : theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                  ),
                  child: Row(
                    children: [
                      Icon(overdue ? Icons.warning_amber_outlined : Icons.event_outlined, color: overdue ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Next Contact', style: theme.textTheme.labelLarge),
                            const SizedBox(height: 2),
                            Text(nextText, style: theme.textTheme.bodyMedium?.copyWith(color: overdue ? theme.colorScheme.error : null)),
                          ],
                        ),
                      ),
                      if (overdue)
                        Text('Overdue', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.error, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: Text('Quick Status', style: theme.textTheme.labelLarge)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (l.status != 'new')
                      OutlinedButton(
                        onPressed: () async {
                          await ref.read(leadsControllerProvider.notifier).updateLead(
                                id: l.id,
                                fullName: l.fullName,
                                phone: l.phone,
                                source: l.source,
                                interest: l.interest,
                                nextContactDate: l.nextContactDate,
                                status: 'new',
                                notes: l.notes,
                              );
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: const Text('Mark New'),
                      ),
                    if (l.status != 'trial')
                      OutlinedButton(
                        onPressed: () async {
                          await ref.read(leadsControllerProvider.notifier).updateLead(
                                id: l.id,
                                fullName: l.fullName,
                                phone: l.phone,
                                source: l.source,
                                interest: l.interest,
                                nextContactDate: l.nextContactDate,
                                status: 'trial',
                                notes: l.notes,
                              );
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: const Text('Mark Trial'),
                      ),
                    if (l.status != 'converted')
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.tertiary),
                        onPressed: () async {
                          await ref.read(leadsControllerProvider.notifier).updateLead(
                                id: l.id,
                                fullName: l.fullName,
                                phone: l.phone,
                                source: l.source,
                                interest: l.interest,
                                nextContactDate: l.nextContactDate,
                                status: 'converted',
                                notes: l.notes,
                              );
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: const Text('Mark Converted'),
                      ),
                    if (l.status != 'lost')
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                        onPressed: () async {
                          await ref.read(leadsControllerProvider.notifier).updateLead(
                                id: l.id,
                                fullName: l.fullName,
                                phone: l.phone,
                                source: l.source,
                                interest: l.interest,
                                nextContactDate: l.nextContactDate,
                                status: 'lost',
                                notes: l.notes,
                              );
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: const Text('Mark Lost'),
                      ),
                  ],
                ),
                if ((l.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: Text('Notes', style: theme.textTheme.labelLarge)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                      color: theme.colorScheme.surface,
                    ),
                    child: Text(l.notes!.trim()),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                final uri = Uri(
                  path: '/members',
                  queryParameters: {
                    'prefill': 'lead',
                    'leadId': l.id.toString(),
                    'fullName': l.fullName,
                    if ((l.phone ?? '').trim().isNotEmpty) 'phone': l.phone!.trim(),
                  },
                );
                context.go(uri.toString());
              },
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Convert'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _openLeadForm(context, lead: l);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
              onPressed: () async {
                final ok = await showAppConfirmDialog(
                  context: context,
                  title: 'Delete lead?',
                  message: l.fullName,
                  confirmLabel: 'Delete',
                  danger: true,
                );
                if (!ok) return;
                if (!context.mounted) return;
                Navigator.of(context).pop();
                await ref.read(leadsControllerProvider.notifier).deleteLead(l.id);
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _applyQuery({String? q, String? status}) {
    final current = ref.read(leadsQueryProvider);
    final next = current.copyWith(q: q ?? current.q, status: status ?? current.status);
    ref.read(leadsQueryProvider.notifier).state = next;
    ref.read(leadsControllerProvider.notifier).load();
  }
 
  bool _matchesNextContact(Lead l, DateTime today) {
    if (_nextContactFilter == 'all') return true;
    final raw = l.nextContactDate?.trim();
    if (raw == null || raw.isEmpty) return false;
    final d = DateTime.tryParse(raw);
    if (d == null) return false;
    final dateOnly = DateTime(d.year, d.month, d.day);
    final t = DateTime(today.year, today.month, today.day);
    if (_nextContactFilter == 'today') return dateOnly == t;
    if (_nextContactFilter == 'tomorrow') return dateOnly == t.add(const Duration(days: 1));
    if (_nextContactFilter == 'next7') return !dateOnly.isBefore(t) && dateOnly.isBefore(t.add(const Duration(days: 7)));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = ref.watch(leadsQueryProvider);
    final async = ref.watch(leadsControllerProvider);
    final qpQ = GoRouterState.of(context).uri.queryParameters['q']?.trim();
    if (!_hydratedFromRoute && qpQ != null && qpQ.isNotEmpty) {
      _hydratedFromRoute = true;
      _searchCtrl.text = qpQ;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyQuery(q: qpQ, status: 'all');
      });
    }
    final itemsPreview = async.valueOrNull ?? const <Lead>[];
    final sources = <String>{
      for (final l in itemsPreview)
        if ((l.source ?? '').trim().isNotEmpty) l.source!.trim(),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final interests = <String>{
      for (final l in itemsPreview)
        if ((l.interest ?? '').trim().isNotEmpty) l.interest!.trim(),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (_searchCtrl.text != q.q) {
      _searchCtrl.text = q.q;
      _searchCtrl.selection = TextSelection.collapsed(offset: _searchCtrl.text.length);
    }
 
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
            Row(
              children: [
                Text('Leads', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  tooltip: 'PDF',
                  onPressed: () => _openLeadsPdfActions(context),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
                FilledButton.icon(
                  onPressed: () => _openLeadForm(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Lead'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 520,
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search (name / phone / source)',
                    ),
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 350), () {
                        _applyQuery(q: v);
                      });
                    },
                    onSubmitted: (v) => _applyQuery(q: v),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey<String>(q.status),
                    initialValue: q.status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All')),
                      DropdownMenuItem(value: 'new', child: Text('New')),
                      DropdownMenuItem(value: 'trial', child: Text('Trial')),
                      DropdownMenuItem(value: 'converted', child: Text('Converted')),
                      DropdownMenuItem(value: 'lost', child: Text('Lost')),
                    ],
                    onChanged: (v) => _applyQuery(status: v ?? 'all'),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(_sourceFilter),
                    initialValue: _sourceFilter,
                    decoration: const InputDecoration(labelText: 'Source'),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All Sources')),
                      for (final s in sources) DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => setState(() => _sourceFilter = v ?? 'all'),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(_interestFilter),
                    initialValue: _interestFilter,
                    decoration: const InputDecoration(labelText: 'Interest'),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All Interests')),
                      for (final s in interests) DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => setState(() => _interestFilter = v ?? 'all'),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => ref.read(leadsControllerProvider.notifier).load(),
                  icon: const Icon(Icons.refresh),
                ),
                OutlinedButton(
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {
                      _overdueOnly = false;
                      _sortByNextContact = true;
                      _sourceFilter = 'all';
                      _interestFilter = 'all';
                      _nextContactFilter = 'all';
                    });
                    _applyQuery(q: '', status: 'all');
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilterChip(
                  selected: _overdueOnly,
                  onSelected: (v) => setState(() => _overdueOnly = v),
                  label: const Text('Overdue'),
                  avatar: const Icon(Icons.warning_amber_outlined, size: 18),
                ),
                FilterChip(
                  selected: _sortByNextContact,
                  onSelected: (v) => setState(() => _sortByNextContact = v),
                  label: const Text('Sort by Next Contact'),
                  avatar: const Icon(Icons.sort_outlined, size: 18),
                ),
                ChoiceChip(
                  label: const Text('Any date'),
                  selected: _nextContactFilter == 'all',
                  onSelected: (_) => setState(() => _nextContactFilter = 'all'),
                ),
                ChoiceChip(
                  label: const Text('Today'),
                  selected: _nextContactFilter == 'today',
                  onSelected: (_) => setState(() => _nextContactFilter = 'today'),
                ),
                ChoiceChip(
                  label: const Text('Tomorrow'),
                  selected: _nextContactFilter == 'tomorrow',
                  onSelected: (_) => setState(() => _nextContactFilter = 'tomorrow'),
                ),
                ChoiceChip(
                  label: const Text('Next 7 days'),
                  selected: _nextContactFilter == 'next7',
                  onSelected: (_) => setState(() => _nextContactFilter = 'next7'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final total = itemsPreview.length;
                final converted = itemsPreview.where((l) => l.status == 'converted').length;
                final level = _computeManagerLevel(converted);
                final progress = level.nextXp <= 0 ? 0.0 : (level.currentXp / level.nextXp).clamp(0.0, 1.0);
                final nextIn = (level.nextXp - level.currentXp).clamp(0, 999999);
                final accent = theme.colorScheme.primary;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: accent.withValues(alpha: 0.12),
                              child: Icon(Icons.auto_graph, color: accent),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Manager Level ${level.level}',
                                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  Text(
                                    'Converted $converted of $total leads • Next level in $nextIn conversions',
                                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                                border: Border.all(color: theme.colorScheme.outlineVariant),
                              ),
                              child: Text(
                                'XP ${level.currentXp}/${level.nextXp}',
                                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 10,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                            valueColor: AlwaysStoppedAnimation<Color>(accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            async.when(
              data: (items) {
                  final today = DateTime.now();
                  final filtered = items
                      .where((l) => !_overdueOnly || _isOverdue(l, today))
                      .where((l) => _sourceFilter == 'all' || (l.source ?? '').trim() == _sourceFilter)
                      .where((l) => _interestFilter == 'all' || (l.interest ?? '').trim() == _interestFilter)
                      .where((l) => _matchesNextContact(l, today))
                      .toList();
                  if (_sortByNextContact) {
                    filtered.sort((a, b) {
                      final ad = (a.nextContactDate == null || a.nextContactDate!.trim().isEmpty)
                          ? null
                          : DateTime.tryParse(a.nextContactDate!.trim());
                      final bd = (b.nextContactDate == null || b.nextContactDate!.trim().isEmpty)
                          ? null
                          : DateTime.tryParse(b.nextContactDate!.trim());
                      if (ad == null && bd == null) return 0;
                      if (ad == null) return 1;
                      if (bd == null) return -1;
                      return ad.compareTo(bd);
                    });
                  }
                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_search_outlined, size: 44, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(height: 10),
                          Text('No leads found', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text('Try changing search / filters', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => _openLeadForm(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Lead'),
                          ),
                        ],
                      ),
                    );
                  }
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                      color: theme.colorScheme.surface,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
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
                          for (final l in filtered)
                            DataRow(
                              cells: [
                                DataCell(
                                  SizedBox(width: 180, child: Text(l.fullName, overflow: TextOverflow.ellipsis)),
                                  onTap: () => _openLeadDetails(context, l),
                                ),
                                DataCell(SizedBox(width: 120, child: Text(l.phone ?? '-', overflow: TextOverflow.ellipsis))),
                                DataCell(SizedBox(width: 140, child: Text(l.source ?? '-', overflow: TextOverflow.ellipsis))),
                                DataCell(SizedBox(width: 160, child: Text(l.interest ?? '-', overflow: TextOverflow.ellipsis))),
                                DataCell(
                                  Text(_fmtDateOnly(l.nextContactDate)),
                                ),
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
                                              'leadId': l.id.toString(),
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
                                        onPressed: () => _openLeadForm(context, lead: l),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete',
                                        onPressed: () async {
                                          final ok = await showAppConfirmDialog(
                                            context: context,
                                            title: 'Delete lead?',
                                            message: l.fullName,
                                            confirmLabel: 'Delete',
                                            danger: true,
                                          );
                                          if (!ok) return;
                                          await ref.read(leadsControllerProvider.notifier).deleteLead(l.id);
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
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(child: Text(e.toString())),
              ),
            ),
          ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surface,
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
