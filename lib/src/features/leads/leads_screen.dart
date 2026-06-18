import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/form_dialog.dart';
import '../../core/providers.dart';
import '../../core/in_app_pdf.dart';
import '../../core/ui_kit.dart';
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
    String? email,
    String? source,
    String? interest,
    String? temperature,
    String? nextContactDate,
    required String status,
    String? notes,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    await api.postJson('/leads', token: token, body: {
      'fullName': fullName.trim(),
      'phone': clean(phone),
      'email': clean(email),
      'source': clean(source),
      'interest': clean(interest),
      'temperature': clean(temperature),
      'nextContactDate': clean(nextContactDate),
      'status': status,
      'notes': clean(notes),
    });
    await load();
  }
 
  Future<void> updateLead({
    required int id,
    required String fullName,
    String? phone,
    String? email,
    String? source,
    String? interest,
    String? temperature,
    String? nextContactDate,
    required String status,
    String? notes,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    await api.patchJson('/leads/$id', token: token, body: {
      'fullName': fullName.trim(),
      'phone': clean(phone),
      'email': clean(email),
      'source': clean(source),
      'interest': clean(interest),
      'temperature': clean(temperature),
      'nextContactDate': clean(nextContactDate),
      'status': status,
      'notes': clean(notes),
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
  bool _quickActionHandled = false;

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
    final c = _statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: c.withAlpha(28),
        border: Border.all(color: c.withAlpha(70), width: 0.8),
      ),
      child: Text(
        status,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: c,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  /// Compact, fixed-height input decoration shared by the search box and every
  /// dropdown. Identical decoration => identical rendered height (40px), which
  /// is what guarantees the filter bar controls line up perfectly.
  InputDecoration _denseDecoration(BuildContext context, {String? hint, Widget? prefixIcon}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: isDark ? Colors.white.withAlpha(28) : Colors.black.withAlpha(28),
        width: 0.8,
      ),
    );
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 13.5, color: theme.colorScheme.onSurfaceVariant),
      prefixIcon: prefixIcon,
      prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      filled: true,
      fillColor: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.2),
      ),
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
      if (!context.mounted) return;
      await presentPdf(context, preview: preview, bytes: bytes, fileName: name, title: 'Leads Report Preview');
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
    final emailCtrl = TextEditingController(text: lead?.email ?? '');
    final notesCtrl = TextEditingController(text: lead?.notes ?? '');
    String status = lead?.status ?? 'new';
    String temperature = (lead?.temperature ?? 'warm').toLowerCase();
    const goalOptions = <String>[
      'Weight Loss',
      'Muscle Gain',
      'Endurance',
      'Strength',
      'General Fitness',
      'Rehab',
    ];
    final fitnessGoals = <String>{
      for (final g in (lead?.interest ?? '').split(',').map((e) => e.trim()))
        if (g.isNotEmpty) g,
    };
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
    final sourceOptions = <String>{
      ...commonSources,
      for (final l in leads)
        if ((l.source ?? '').trim().isNotEmpty) l.source!.trim(),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    TextEditingController? sourceAutoCtrl;
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FormSectionLabel(
                  'Lead Profile',
                  hint: 'Capture contact details to power automated email nurture sequences.',
                  icon: Icons.badge_outlined,
                ),
                const SizedBox(height: 16),
                FormRow([
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      hintText: 'e.g. Ayesha Khan',
                    ),
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Enter name' : null,
                  ),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      hintText: 'Primary contact number',
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                FormRow([
                  TextFormField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      hintText: 'For automated marketing sequences',
                    ),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return null;
                      return s.contains('@') ? null : 'Invalid email';
                    },
                  ),
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
                        decoration: const InputDecoration(
                          labelText: 'Referral Source',
                          hintText: 'Instagram, Walk-in, Member Referral...',
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 16),
                FormMultiChips(
                  label: 'Fitness Goals',
                  hint: 'Select all that apply — personalises nurture messaging.',
                  options: goalOptions,
                  selected: fitnessGoals,
                  accent: const Color(0xFF10B981),
                  onToggle: (g) => setModalState(() {
                    if (fitnessGoals.contains(g)) {
                      fitnessGoals.remove(g);
                    } else {
                      fitnessGoals.add(g);
                    }
                  }),
                ),
                const SizedBox(height: 16),
                FormSegmented<String>(
                  label: 'Lead Temperature',
                  value: temperature,
                  onChanged: (v) => setModalState(() => temperature = v),
                  segments: const [
                    FormSegment('cold', 'Cold', icon: Icons.ac_unit, color: Color(0xFF2563EB)),
                    FormSegment('warm', 'Warm', icon: Icons.wb_sunny_outlined, color: Color(0xFFF59E0B)),
                    FormSegment('hot', 'Hot', icon: Icons.local_fire_department_outlined, color: Color(0xFFDC2626)),
                  ],
                ),
                const SizedBox(height: 18),
                const FormSectionLabel('Follow-up', icon: Icons.event_available_outlined),
                const SizedBox(height: 12),
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
                const SizedBox(height: 16),
                FormRow([
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
                ]),
                const SizedBox(height: 16),
                TextFormField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Add preferred timings, budget, objections, or any context for the sales team.',
                    alignLabelWithHint: true,
                  ),
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
            final interest = fitnessGoals.join(', ');
            if (isEdit) {
              await controller.updateLead(
                id: lead.id,
                fullName: nameCtrl.text,
                phone: phoneCtrl.text,
                email: emailCtrl.text,
                source: source,
                interest: interest,
                temperature: temperature,
                nextContactDate: nextContact == null ? null : date.format(nextContact!),
                status: status,
                notes: notesCtrl.text,
              );
            } else {
              await controller.addLead(
                fullName: nameCtrl.text,
                phone: phoneCtrl.text,
                email: emailCtrl.text,
                source: source,
                interest: interest,
                temperature: temperature,
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
      emailCtrl.dispose();
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
                                email: l.email,
                                source: l.source,
                                interest: l.interest,
                                temperature: l.temperature,
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
                                email: l.email,
                                source: l.source,
                                interest: l.interest,
                                temperature: l.temperature,
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
                                email: l.email,
                                source: l.source,
                                interest: l.interest,
                                temperature: l.temperature,
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
                                email: l.email,
                                source: l.source,
                                interest: l.interest,
                                temperature: l.temperature,
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
    // Global "+" Quick Action → open Add Lead modal once on arrival.
    final pendingAction = ref.watch(pendingQuickActionProvider);
    if (pendingAction == null) {
      _quickActionHandled = false;
    } else if (pendingAction == QuickAction.addLead && !_quickActionHandled) {
      _quickActionHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        ref.read(pendingQuickActionProvider.notifier).state = null;
        await _openLeadForm(context);
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
            // ── Aligned filter controls bar ─────────────────────────────────
            // Every control shares _denseDecoration => identical 40px heights,
            // wrapped in _LabeledFilter so captions sit on one baseline.
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _LabeledFilter(
                  label: 'Search',
                  width: 340,
                  child: TextField(
                    controller: _searchCtrl,
                    style: GoogleFonts.inter(fontSize: 13.5),
                    decoration: _denseDecoration(
                      context,
                      hint: 'Name / phone / source',
                      prefixIcon: Icon(Icons.search, size: 18, color: theme.colorScheme.onSurfaceVariant),
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
                _LabeledFilter(
                  label: 'Status',
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey<String>(q.status),
                    initialValue: q.status,
                    isDense: true,
                    isExpanded: true,
                    style: GoogleFonts.inter(fontSize: 13.5, color: theme.colorScheme.onSurface),
                    decoration: _denseDecoration(context),
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
                _LabeledFilter(
                  label: 'Source',
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(_sourceFilter),
                    initialValue: _sourceFilter,
                    isDense: true,
                    isExpanded: true,
                    style: GoogleFonts.inter(fontSize: 13.5, color: theme.colorScheme.onSurface),
                    decoration: _denseDecoration(context),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All sources')),
                      for (final s in sources) DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => setState(() => _sourceFilter = v ?? 'all'),
                  ),
                ),
                _LabeledFilter(
                  label: 'Interest',
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(_interestFilter),
                    initialValue: _interestFilter,
                    isDense: true,
                    isExpanded: true,
                    style: GoogleFonts.inter(fontSize: 13.5, color: theme.colorScheme.onSurface),
                    decoration: _denseDecoration(context),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All interests')),
                      for (final s in interests) DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => setState(() => _interestFilter = v ?? 'all'),
                  ),
                ),
                // Trailing actions — empty caption keeps them on the field baseline.
                _LabeledFilter(
                  label: '',
                  width: 150,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => ref.read(leadsControllerProvider.notifier).load(),
                          icon: const Icon(Icons.refresh, size: 17),
                          label: const Text('Refresh'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            side: BorderSide(
                              color: theme.brightness == Brightness.dark
                                  ? Colors.white.withAlpha(28)
                                  : Colors.black.withAlpha(28),
                              width: 0.8,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── Low-profile filter tags — single swipe-scrollable line ──────
            AppHScroll(
              children: [
                _FilterPill(
                  label: 'Overdue',
                  icon: Icons.warning_amber_rounded,
                  selected: _overdueOnly,
                  // Amber, not red — it is a warning filter, not an emergency block.
                  accentOverride: const Color(0xFFF59E0B),
                  onTap: () => setState(() => _overdueOnly = !_overdueOnly),
                ),
                _FilterPill(
                  label: 'Sort by Next Contact',
                  icon: Icons.sort_rounded,
                  selected: _sortByNextContact,
                  onTap: () => setState(() => _sortByNextContact = !_sortByNextContact),
                ),
                _FilterPill(
                  label: 'Any date',
                  selected: _nextContactFilter == 'all',
                  onTap: () => setState(() => _nextContactFilter = 'all'),
                ),
                _FilterPill(
                  label: 'Today',
                  selected: _nextContactFilter == 'today',
                  onTap: () => setState(() => _nextContactFilter = 'today'),
                ),
                _FilterPill(
                  label: 'Tomorrow',
                  selected: _nextContactFilter == 'tomorrow',
                  onTap: () => setState(() => _nextContactFilter = 'tomorrow'),
                ),
                _FilterPill(
                  label: 'Next 7 days',
                  selected: _nextContactFilter == 'next7',
                  onTap: () => setState(() => _nextContactFilter = 'next7'),
                ),
                const SizedBox(width: 4),
                // Inline "Clear all" text action — replaces the old Clear button.
                _FilterPill(
                  label: 'Clear',
                  icon: Icons.close_rounded,
                  selected: false,
                  onTap: () {
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
                  // Faint divider tint — grey.shade200 in light, faint white in dark.
                  final dividerTint = theme.brightness == Brightness.dark
                      ? Colors.white.withAlpha(15)
                      : Colors.grey.shade200;
                  // Inter typography for all table cells — crisp tabular alignment.
                  final headingStyle = GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: theme.colorScheme.onSurfaceVariant,
                  );
                  final cellStyle = GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurface,
                  );
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: dividerTint, width: 1),
                      color: theme.colorScheme.surface,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Theme(
                        // Scope the faint-divider + Inter overrides to this table only.
                        data: theme.copyWith(
                          dividerColor: dividerTint,
                          dataTableTheme: DataTableThemeData(
                            dividerThickness: 1,
                            headingTextStyle: headingStyle,
                            dataTextStyle: cellStyle,
                            headingRowColor: WidgetStatePropertyAll(
                              theme.brightness == Brightness.dark
                                  ? Colors.white.withAlpha(8)
                                  : Colors.black.withAlpha(5),
                            ),
                          ),
                        ),
                        child: DataTable(
                        columnSpacing: 18,
                        horizontalMargin: 16,
                        headingRowHeight: 46,
                        dataRowMinHeight: 52,
                        dataRowMaxHeight: 58,
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
                                      _TableActionButton(
                                        tooltip: 'Convert to Member',
                                        icon: Icons.person_add_alt_1_outlined,
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
                                      ),
                                      const SizedBox(width: 2),
                                      _TableActionButton(
                                        tooltip: 'Edit',
                                        icon: Icons.edit_outlined,
                                        onPressed: () => _openLeadForm(context, lead: l),
                                      ),
                                      const SizedBox(width: 2),
                                      _TableActionButton(
                                        tooltip: 'Delete',
                                        icon: Icons.delete_outline,
                                        danger: true,
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
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
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

/// A filter control with a small caption above and a fixed 40px-tall field.
/// All filter controls share this wrapper so their field heights are identical
/// and their captions sit on one baseline — the "aligned filter bar" look.
class _LabeledFilter extends StatelessWidget {
  const _LabeledFilter({
    required this.label,
    required this.width,
    required this.child,
  });

  final String label;
  final double width;
  final Widget child;

  /// Shared field height for every filter control. Single source of truth.
  static const double fieldHeight = 40;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              // Non-breaking space keeps the caption row height for unlabeled
              // trailing controls (Refresh / Clear) so they align with fields.
              label.isEmpty ? ' ' : label.toUpperCase(),
              style: AppTypography.uiLabel(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
                weight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SizedBox(height: fieldHeight, child: child),
        ],
      ),
    );
  }
}

/// Flat, low-profile filter tag (HubSpot / Retool style).
/// Selected → subtle accent tint + accent border + accent text.
/// Unselected → transparent fill + faint hairline border + muted text.
/// No full-bleed red blocks — accent stays a signal, not a background.
class _FilterPill extends StatefulWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.accentOverride,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// Optional accent (e.g. amber for the "Overdue" warning filter).
  final Color? accentOverride;

  @override
  State<_FilterPill> createState() => _FilterPillState();
}

class _FilterPillState extends State<_FilterPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = widget.accentOverride ?? theme.colorScheme.primary;

    late final Color bg;
    late final Color border;
    late final Color fg;
    if (widget.selected) {
      bg = accent.withAlpha(isDark ? 30 : 22);
      border = accent.withAlpha(isDark ? 130 : 95);
      fg = accent;
    } else {
      bg = _hover
          ? (isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8))
          : Colors.transparent;
      // Subtle hairline — grey.shade300 equivalent, theme-adaptive.
      border = isDark ? Colors.white.withAlpha(33) : Colors.black.withAlpha(33);
      fg = theme.colorScheme.onSurfaceVariant;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: AppTypography.uiLabel(
                  color: fg,
                  fontSize: 12.5,
                  weight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Table row action icon with a translucent circular backdrop on hover.
/// `danger` variant fades to a soft muted red only while hovered.
class _TableActionButton extends StatefulWidget {
  const _TableActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool danger;

  @override
  State<_TableActionButton> createState() => _TableActionButtonState();
}

class _TableActionButtonState extends State<_TableActionButton> {
  bool _hover = false;

  // Soft muted red — not the harsh error red. Only shown on delete-hover.
  static const Color _mutedRed = Color(0xFFE06C6C);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color fg = _hover
        ? (widget.danger ? _mutedRed : theme.colorScheme.onSurface)
        : theme.colorScheme.onSurfaceVariant;

    final Color bg = !_hover
        ? Colors.transparent
        : widget.danger
            ? _mutedRed.withAlpha(28)
            : (isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(12));

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            width: 34,
            height: 34,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
            child: Icon(widget.icon, size: 18, color: fg),
          ),
        ),
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
