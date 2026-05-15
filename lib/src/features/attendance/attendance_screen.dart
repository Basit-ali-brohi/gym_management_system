import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/web_download_stub.dart' if (dart.library.html) '../../core/web_download_web.dart';
import '../../models/models.dart';
import '../auth/auth_controller.dart';

final attendanceControllerProvider =
    StateNotifierProvider.autoDispose<AttendanceController, AsyncValue<_AttendancePage>>((ref) {
  return AttendanceController(ref)..loadToday();
});

final memberSearchProvider =
    StateNotifierProvider.autoDispose<MemberSearchController, AsyncValue<List<Member>>>((ref) {
  return MemberSearchController(ref);
});

class _AttendancePage {
  const _AttendancePage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.range,
    required this.q,
    required this.sort,
  });

  const _AttendancePage.empty()
      : items = const [],
        total = 0,
        limit = 50,
        offset = 0,
        range = 'today',
        q = '',
        sort = 'newest';

  final List<AttendanceLog> items;
  final int total;
  final int limit;
  final int offset;
  final String range;
  final String q;
  final String sort;
}

class AttendanceController extends StateNotifier<AsyncValue<_AttendancePage>> {
  AttendanceController(this.ref) : super(const AsyncValue.loading());

  final Ref ref;
  String _range = 'today';
  String _q = '';
  String _sort = 'newest';
  final int _limit = 50;
  int _offset = 0;

  Future<void> loadRange({required String range}) async {
    _range = range;
    _offset = 0;
    await load();
  }

  Future<void> setSort(String sort) async {
    _sort = sort;
    _offset = 0;
    await load();
  }

  Future<void> setQuery(String q) async {
    _q = q.trim();
    _offset = 0;
    await load();
  }

  Future<void> nextPage() async {
    final page = state.valueOrNull;
    final total = page?.total ?? 0;
    final next = _offset + _limit;
    if (next >= total) return;
    _offset = next;
    await load();
  }

  Future<void> prevPage() async {
    _offset = max(0, _offset - _limit);
    await load();
  }

  Future<void> load() async {
    state = const AsyncLoading<_AttendancePage>().copyWithPrevious(state);
    try {
      final token = ref.read(authControllerProvider).token;
      final api = ref.read(apiClientProvider);
      final query = <String, String>{
        'range': _range,
        'limit': _limit.toString(),
        'offset': _offset.toString(),
        'sort': _sort,
      };
      if (_q.isNotEmpty) query['q'] = _q;
      final res = await api.getJson('/attendance', token: token, query: query);
      final items = (res['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => AttendanceLog.fromJson(e.cast<String, dynamic>()))
          .toList();
      final total = (res['total'] as num?)?.toInt() ?? items.length;
      state = AsyncValue.data(
        _AttendancePage(
          items: items,
          total: total,
          limit: _limit,
          offset: _offset,
          range: _range,
          q: _q,
          sort: _sort,
        ),
      );
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error('attendance_load_failed', st);
    }
  }

  Future<void> loadToday() async {
    await loadRange(range: 'today');
  }

  Future<CheckInResult> checkIn({required int memberId}) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    final res = await api.postJson('/attendance/checkin', token: token, body: {'memberId': memberId});
    if ((res['allowed'] as bool?) == true) {
      await load();
    }
    return CheckInResult.fromJson(res);
  }

  Future<CheckInResult> checkInByQuery({required String query}) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    final res = await api.postJson('/attendance/checkin', token: token, body: {'query': query.trim()});
    if ((res['allowed'] as bool?) == true) {
      await load();
    }
    return CheckInResult.fromJson(res);
  }
}

class CheckInResult {
  const CheckInResult({
    required this.allowed,
    required this.alreadyCheckedIn,
    required this.reason,
    required this.membershipEndDate,
    required this.frozenUntil,
    required this.unpaidInvoices,
    required this.memberName,
    required this.memberCode,
  });

  final bool allowed;
  final bool alreadyCheckedIn;
  final String? reason;
  final String? membershipEndDate;
  final String? frozenUntil;
  final int unpaidInvoices;
  final String? memberName;
  final String? memberCode;

  factory CheckInResult.fromJson(Map<String, dynamic> json) {
    return CheckInResult(
      allowed: json['allowed'] as bool? ?? false,
      alreadyCheckedIn: json['alreadyCheckedIn'] as bool? ?? false,
      reason: json['reason']?.toString(),
      membershipEndDate: json['membershipEndDate']?.toString(),
      frozenUntil: json['frozenUntil']?.toString(),
      unpaidInvoices: (json['unpaidInvoices'] as num?)?.toInt() ?? 0,
      memberName: json['memberName']?.toString(),
      memberCode: json['memberCode']?.toString(),
    );
  }
}

class ValidateAccessResult {
  const ValidateAccessResult({
    required this.allowed,
    required this.reason,
    required this.memberName,
    required this.memberCode,
    required this.membershipEndDate,
    required this.unpaidInvoices,
    required this.planName,
    required this.frozenUntil,
  });

  final bool allowed;
  final String? reason;
  final String? memberName;
  final String? memberCode;
  final String? membershipEndDate;
  final int unpaidInvoices;
  final String? planName;
  final String? frozenUntil;

  factory ValidateAccessResult.fromJson(Map<String, dynamic> json) {
    final member = json['member'] is Map ? (json['member'] as Map).cast<String, dynamic>() : null;
    final plan = json['plan'] is Map ? (json['plan'] as Map).cast<String, dynamic>() : null;
    return ValidateAccessResult(
      allowed: json['allowed'] as bool? ?? false,
      reason: json['reason']?.toString(),
      memberName: member?['fullName']?.toString(),
      memberCode: member?['memberCode']?.toString(),
      membershipEndDate: plan?['endDate']?.toString(),
      unpaidInvoices: (json['unpaidInvoices'] as num?)?.toInt() ?? 0,
      planName: plan?['name']?.toString(),
      frozenUntil: json['frozenUntil']?.toString(),
    );
  }
}

class MemberSearchController extends StateNotifier<AsyncValue<List<Member>>> {
  MemberSearchController(this.ref) : super(const AsyncValue.data([]));

  final Ref ref;
  String _lastQuery = '';

  String get lastQuery => _lastQuery;

  Future<void> search(String q) async {
    final query = q.trim();
    _lastQuery = query;
    if (query.isEmpty) {
      state = const AsyncValue.data([]);
      return;
    }

    state = const AsyncValue.loading();
    try {
      final token = ref.read(authControllerProvider).token;
      final api = ref.read(apiClientProvider);
      final res = await api.getJson('/members', token: token, query: {'q': query, 'limit': '20'});
      final items = (res['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Member.fromJson(e.cast<String, dynamic>()))
          .toList();
      state = AsyncValue.data(items);
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error('search_failed', st);
    }
  }
}

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> with SingleTickerProviderStateMixin {
  final _codeCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _logSearchCtrl = TextEditingController();
  Timer? _debounce;
  Timer? _codeDebounce;
  Timer? _borderReset;
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;
  Color? _panelBorderColor;
  ValidateAccessResult? _accessPreview;
  bool _accessLoading = false;
  String _lastAccessQuery = '';
  String _range = 'today';
  String _sort = 'newest';
  final _dt = DateFormat('yyyy-MM-dd HH:mm');
  final _date = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _codeDebounce?.cancel();
    _borderReset?.cancel();
    _shakeCtrl.dispose();
    _codeCtrl.dispose();
    _searchCtrl.dispose();
    _logSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attendanceAsync = ref.watch(attendanceControllerProvider);
    final theme = Theme.of(context);
    final searchAsync = ref.watch(memberSearchProvider);
    final pagePreview = attendanceAsync.valueOrNull ?? const _AttendancePage.empty();
    final itemsPreview = pagePreview.items;
    final total = pagePreview.total;
    final unique = itemsPreview.map((e) => e.memberId).toSet().length;
    DateTime? latest;
    for (final a in itemsPreview) {
      final t = DateTime.tryParse(a.checkedInAt);
      if (t == null) continue;
      if (latest == null || t.isAfter(latest)) latest = t;
    }
    final latestLabel = latest == null ? '-' : _dt.format(latest);
    final rangeLabel = _range == 'today' ? "Today's" : (_range == '7d' ? 'Last 7 days' : 'Last 30 days');

    String fmtAvgSession() {
      final durations = <Duration>[];
      for (final a in itemsPreview) {
        final i = DateTime.tryParse(a.checkedInAt);
        final o = a.checkedOutAt == null ? null : DateTime.tryParse(a.checkedOutAt!);
        if (i == null || o == null) continue;
        final d = o.difference(i);
        if (d.isNegative) continue;
        durations.add(d);
      }
      if (durations.isEmpty) return '-';
      final totalMs = durations.map((d) => d.inMilliseconds).reduce((a, b) => a + b);
      final avg = Duration(milliseconds: (totalMs / durations.length).round());
      final h = avg.inHours;
      final m = avg.inMinutes.remainder(60);
      if (h <= 0) return '${m}m';
      return '${h}h ${m}m';
    }

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

    final goldBorder = theme.cardTheme.shape is RoundedRectangleBorder
        ? (theme.cardTheme.shape as RoundedRectangleBorder).side
        : BorderSide(color: theme.colorScheme.outlineVariant);

    final searchPanelInner = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Check-in', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Member Code',
                    prefixIcon: Icon(Icons.badge),
                  ),
                  onChanged: (v) => _scheduleValidate(v),
                  onSubmitted: (v) => _checkInByCode(v),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () => _checkInByCode(_codeCtrl.text),
                child: const Text('Check-in'),
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _codeCtrl.text.trim().isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _AccessPreviewCard(
                      loading: _accessLoading,
                      preview: _accessPreview,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              labelText: 'Instant search (code / name / phone)',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: () => ref.read(memberSearchProvider.notifier).search(_searchCtrl.text),
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 220), () {
                ref.read(memberSearchProvider.notifier).search(v);
              });
            },
            onSubmitted: (v) => ref.read(memberSearchProvider.notifier).search(v),
          ),
          const SizedBox(height: 12),
          searchAsync.when(
            data: (items) {
              if (_searchCtrl.text.trim().isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: Text('Type to filter members', style: theme.textTheme.bodySmall)),
                );
              }
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: Text('No results', style: theme.textTheme.bodySmall)),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final m = items[i];
                  return ListTile(
                    dense: true,
                    title: Text('${m.fullName} (${m.memberCode})'),
                    subtitle: Text([
                      'ID: ${m.id}',
                      if (m.phone != null && m.phone!.isNotEmpty) m.phone!,
                      if (m.email != null && m.email!.isNotEmpty) m.email!,
                    ].join(' • ')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'View',
                          onPressed: () => _openMemberView(context, m.id),
                          icon: const Icon(Icons.visibility),
                        ),
                        FilledButton(
                          onPressed: () => _checkIn(context, m),
                          child: const Text('Check-in'),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            error: (e, _) => Center(child: Text(e.toString())),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );

    final searchPanel = AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (context, child) {
        final border = BorderSide(
          color: _panelBorderColor ?? goldBorder.color,
          width: _panelBorderColor == null ? goldBorder.width : 1.6,
        );
        return Transform.translate(
          offset: Offset(_shakeAnim.value, 0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.fromBorderSide(border),
              color: theme.cardTheme.color,
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        );
      },
      child: searchPanelInner,
    );

    final todayPanel = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text("Today's Attendance", style: theme.textTheme.titleMedium)),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => ref.read(attendanceControllerProvider.notifier).load(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            attendanceAsync.when(
              data: (page) {
                final items = page.items;
                if (items.isEmpty) {
                  return _EmptyState(
                    icon: Icons.how_to_reg,
                    title: 'No data found',
                    subtitle: _range == 'today' ? 'No check-ins today' : 'No logs in this range',
                  );
                }
                final fromN = page.total == 0 ? 0 : page.offset + 1;
                final toN = min(page.offset + items.length, page.total);
                final canPrev = page.offset > 0;
                final canNext = page.offset + items.length < page.total;
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length + 1,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                        child: Row(
                          children: [
                            Text(
                              page.total == 0 ? '—' : 'Showing $fromN–$toN of ${page.total}',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Previous',
                              onPressed: canPrev ? () => ref.read(attendanceControllerProvider.notifier).prevPage() : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            IconButton(
                              tooltip: 'Next',
                              onPressed: canNext ? () => ref.read(attendanceControllerProvider.notifier).nextPage() : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      );
                    }

                    final a = items[i - 1];
                    final checkedIn = DateTime.tryParse(a.checkedInAt);
                    final checkedOut = a.checkedOutAt != null ? DateTime.tryParse(a.checkedOutAt!) : null;
                    final inText = checkedIn == null ? a.checkedInAt : _dt.format(checkedIn);
                    final outText = checkedOut == null ? null : _dt.format(checkedOut);
                    return ListTile(
                      leading: const Icon(Icons.how_to_reg),
                      title: Text('${a.fullName} (${a.memberCode})'),
                      subtitle: Text('In: $inText${outText != null ? ' • Out: $outText' : ''}'),
                      trailing: IconButton(
                        tooltip: 'View',
                        onPressed: () => _openMemberView(context, a.memberId),
                        icon: const Icon(Icons.visibility),
                      ),
                    );
                  },
                );
              },
              error: (e, _) => Center(child: Text(e.toString())),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: Text('Attendance', style: theme.textTheme.headlineSmall)),
            IconButton(
              tooltip: 'PDF',
              onPressed: () => _openAttendancePdfActions(context),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.read(attendanceControllerProvider.notifier).load(),
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
              title: '$rangeLabel Check-ins',
              value: '$total',
              subtitle: 'Attendance',
              icon: Icons.how_to_reg,
            ),
            metricCard(
              title: 'Unique members',
              value: '$unique',
              subtitle: 'Checked-in users',
              icon: Icons.groups_outlined,
            ),
            metricCard(
              title: 'Latest check-in',
              value: latestLabel,
              subtitle: 'Most recent',
              icon: Icons.schedule_outlined,
            ),
            metricCard(
              title: 'Avg session',
              value: fmtAvgSession(),
              subtitle: 'Based on check-outs',
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
                    key: ValueKey(_range),
                    initialValue: _range,
                    decoration: const InputDecoration(labelText: 'Range'),
                    items: const [
                      DropdownMenuItem(value: 'today', child: Text('Today')),
                      DropdownMenuItem(value: '7d', child: Text('Last 7 days')),
                      DropdownMenuItem(value: '30d', child: Text('Last 30 days')),
                    ],
                    onChanged: (v) {
                      final next = v ?? 'today';
                      setState(() => _range = next);
                      ref.read(attendanceControllerProvider.notifier).loadRange(range: next);
                    },
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(_sort),
                    initialValue: _sort,
                    decoration: const InputDecoration(labelText: 'Sort'),
                    items: const [
                      DropdownMenuItem(value: 'newest', child: Text('Newest')),
                      DropdownMenuItem(value: 'oldest', child: Text('Oldest')),
                    ],
                    onChanged: (v) {
                      final next = v ?? 'newest';
                      setState(() => _sort = next);
                      ref.read(attendanceControllerProvider.notifier).setSort(next);
                    },
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: TextField(
                    controller: _logSearchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search member, code',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 320), () {
                        ref.read(attendanceControllerProvider.notifier).setQuery(_logSearchCtrl.text);
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1100) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: searchPanel),
                  const SizedBox(width: 12),
                  Expanded(flex: 7, child: todayPanel),
                ],
              );
            }
            return Column(
              children: [
                searchPanel,
                const SizedBox(height: 12),
                todayPanel,
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _openAttendancePdfActions(BuildContext context) async {
    final today = _date.format(DateTime.now());
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Attendance PDF'),
          content: Text('Date: $today'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runAttendancePdf(context, preview: true, date: today);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runAttendancePdf(context, preview: false, date: today);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runAttendancePdf(BuildContext context, {required bool preview, required String date}) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final bytes = await api.getBytes('/pdf/attendance.pdf', token: token, query: {'date': date});
      final name = 'attendance_$date.pdf';
      final savedPath = preview
          ? previewBytes(fileName: name, bytes: bytes, mimeType: 'application/pdf')
          : downloadBytes(fileName: name, bytes: bytes, mimeType: 'application/pdf');
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF failed')));
    }
  }

  Future<void> _checkIn(BuildContext context, Member member) async {
    final fullName = member.fullName;
    try {
      final result = await ref.read(attendanceControllerProvider.notifier).checkIn(memberId: member.id);
      if (!context.mounted) return;
      if (!result.allowed) {
        _setDeniedBorder();
        SystemSound.play(SystemSoundType.alert);

        final reason = result.reason ?? 'not_allowed';
        final title = reason == 'membership_expired'
            ? 'Membership Expired'
            : reason == 'fees_pending'
                ? 'Fees Pending'
                : reason == 'membership_frozen'
                    ? 'Membership Frozen'
                    : 'Access Denied';
        final body = reason == 'membership_expired'
            ? 'Membership expired${result.membershipEndDate != null ? ' (Expiry: ${result.membershipEndDate})' : ''}.'
            : reason == 'fees_pending'
                ? 'Unpaid invoices: ${result.unpaidInvoices}.'
                : reason == 'membership_frozen'
                    ? 'Membership is frozen${result.frozenUntil != null ? ' (Until: ${result.frozenUntil})' : ''}.'
                    : 'Not allowed.';

        await showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(title),
              content: Text(body),
              icon: const Icon(Icons.error_outline, color: Colors.redAccent),
              actions: [
                FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
              ],
            );
          },
        );
        return;
      }

      _setSuccessBorder();

      final initials = fullName
          .trim()
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .take(2)
          .map((s) => s[0].toUpperCase())
          .join();

      final expiry = result.membershipEndDate;
      final goBilling = await showDialog<bool>(
        context: context,
        builder: (context) {
          final unpaid = result.unpaidInvoices;
          return AlertDialog(
            icon: Icon(Icons.verified, color: Theme.of(context).colorScheme.tertiary),
            title: Text(result.alreadyCheckedIn ? 'Already Checked-in' : 'Access Granted'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 26,
                  child: Text(initials.isEmpty ? 'M' : initials),
                ),
                const SizedBox(height: 10),
                Text(fullName, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(expiry == null ? 'Expiry: -' : 'Expiry: $expiry'),
                if (unpaid > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Fees pending: $unpaid unpaid invoice(s).',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.tertiary,
                          fontWeight: FontWeight.w700,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
            actions: [
              if (result.unpaidInvoices > 0)
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('No')),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(result.unpaidInvoices > 0),
                child: Text(result.unpaidInvoices > 0 ? 'Yes' : 'OK'),
              ),
            ],
          );
        },
      );
      if (goBilling == true && context.mounted) {
        context.go('/invoices?q=${Uri.encodeComponent(member.memberCode)}');
      }
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check-in failed')));
    }
  }

  Future<void> _checkInByCode(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;
    try {
      final result = await ref.read(attendanceControllerProvider.notifier).checkInByQuery(query: code);
      if (!mounted) return;
      if (!result.allowed) {
        _setDeniedBorder();
        SystemSound.play(SystemSoundType.alert);

        final reason = result.reason ?? 'not_allowed';
        final title = reason == 'membership_expired' ? 'Membership Expired' : reason == 'fees_pending' ? 'Fees Pending' : 'Access Denied';
        final body = reason == 'membership_expired'
            ? 'Membership expired${result.membershipEndDate != null ? ' (Expiry: ${result.membershipEndDate})' : ''}.'
            : reason == 'fees_pending'
                ? 'Unpaid invoices: ${result.unpaidInvoices}.'
                : reason == 'membership_frozen'
                    ? 'Membership is frozen${result.frozenUntil != null ? ' (Until: ${result.frozenUntil})' : ''}.'
                : 'Not allowed.';

        await showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(title),
              content: Text(body),
              icon: const Icon(Icons.error_outline, color: Colors.redAccent),
              actions: [
                FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
              ],
            );
          },
        );
        return;
      }

      _setSuccessBorder();
      final fullName = result.memberName ?? 'Member';
      final initials = fullName
          .trim()
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .take(2)
          .map((s) => s[0].toUpperCase())
          .join();

      final goBilling = await showDialog<bool>(
        context: context,
        builder: (context) {
          final unpaid = result.unpaidInvoices;
          return AlertDialog(
            icon: Icon(Icons.verified, color: Theme.of(context).colorScheme.tertiary),
            title: Text(result.alreadyCheckedIn ? 'Already Checked-in' : 'Access Granted'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(radius: 26, child: Text(initials.isEmpty ? 'M' : initials)),
                const SizedBox(height: 10),
                Text(fullName, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(result.membershipEndDate == null ? 'Expiry: -' : 'Expiry: ${result.membershipEndDate}'),
                if (unpaid > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Fees pending: $unpaid unpaid invoice(s).',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.tertiary,
                          fontWeight: FontWeight.w700,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
            actions: [
              if (result.unpaidInvoices > 0)
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('No')),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(result.unpaidInvoices > 0),
                child: Text(result.unpaidInvoices > 0 ? 'Yes' : 'OK'),
              ),
            ],
          );
        },
      );
      if (goBilling == true && mounted) {
        final mc = result.memberCode ?? '';
        if (mc.trim().isNotEmpty) {
          context.go('/invoices?q=${Uri.encodeComponent(mc)}');
        } else {
          context.go('/invoices');
        }
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      _setDeniedBorder();
      SystemSound.play(SystemSoundType.alert);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      _setDeniedBorder();
      SystemSound.play(SystemSoundType.alert);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Search failed')));
    }
  }

  void _setDeniedBorder() {
    _borderReset?.cancel();
    setState(() => _panelBorderColor = Colors.redAccent);
    _shakeCtrl.forward(from: 0);
    _borderReset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _panelBorderColor = null);
    });
  }

  void _setSuccessBorder() {
    _borderReset?.cancel();
    setState(() => _panelBorderColor = const Color(0xFF10B981));
    _borderReset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _panelBorderColor = null);
    });
  }

  void _scheduleValidate(String raw) {
    if (mounted) setState(() {});
    _codeDebounce?.cancel();
    _codeDebounce = Timer(const Duration(milliseconds: 240), () {
      _validateAccess(raw);
    });
  }

  Future<void> _validateAccess(String raw) async {
    final q = raw.trim();
    _lastAccessQuery = q;
    if (q.isEmpty) {
      if (!mounted) return;
      setState(() {
        _accessLoading = false;
        _accessPreview = null;
      });
      return;
    }

    setState(() => _accessLoading = true);
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final res = await api.getJson('/sentinel/validate', token: token, query: {'q': q});
      final parsed = ValidateAccessResult.fromJson(res);
      if (!mounted) return;
      if (_lastAccessQuery != q) return;
      setState(() {
        _accessPreview = parsed;
        _accessLoading = false;
      });
    } on ApiException {
      if (!mounted) return;
      if (_lastAccessQuery != q) return;
      setState(() {
        _accessPreview = null;
        _accessLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (_lastAccessQuery != q) return;
      setState(() {
        _accessPreview = null;
        _accessLoading = false;
      });
    }
  }

  Future<void> _openMemberView(BuildContext context, int memberId) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final res = await api.getJson('/members/$memberId/detail', token: token);
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) {
          final m = res['member'] is Map ? (res['member'] as Map).cast<String, dynamic>() : res;
          final sub = res['subscription'] is Map ? (res['subscription'] as Map).cast<String, dynamic>() : null;
          final frozenUntil = m['frozenUntil']?.toString();
          return AlertDialog(
            title: Text(m['fullName']?.toString() ?? 'Member'),
            content: Text(
              [
                'Code: ${m['memberCode'] ?? '-'}',
                if (m['phone'] != null) 'Phone: ${m['phone']}',
                if (sub != null) 'Plan: ${sub['planName']}',
                if (sub != null) 'Expiry: ${sub['endDate']}',
                if (frozenUntil != null && frozenUntil.trim().isNotEmpty) 'Frozen until: $frozenUntil',
                'Status: ${m['status'] ?? '-'}',
              ].join('\n'),
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
            ],
          );
        },
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
    }
  }
}

class _AccessPreviewCard extends StatelessWidget {
  const _AccessPreviewCard({required this.loading, required this.preview});

  final bool loading;
  final ValidateAccessResult? preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = preview;

    if (loading && p == null) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    if (p == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          color: theme.colorScheme.surface.withAlpha(40),
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Status check ready…',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final ok = p.allowed;
    final green = const Color(0xFF10B981);
    final red = theme.colorScheme.error;

    final child = Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: ok ? green.withAlpha(44) : red.withAlpha(44),
            child: Icon(ok ? Icons.verified : Icons.block, color: ok ? green : red),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.memberName?.isNotEmpty == true ? p.memberName! : 'Member',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (p.memberCode?.isNotEmpty == true) 'Code: ${p.memberCode}',
                    if (p.planName?.isNotEmpty == true) 'Plan: ${p.planName}',
                    if (p.membershipEndDate?.isNotEmpty == true) 'Expiry: ${p.membershipEndDate}',
                    if (!ok && p.reason == 'fees_pending') 'Unpaid: ${p.unpaidInvoices}',
                    if (!ok && p.reason == 'membership_expired') 'Expired',
                  ].join(' • '),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (loading) const SizedBox(width: 12),
          if (loading) const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );

    if (ok) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: green, width: 1.6),
          boxShadow: [
            BoxShadow(color: const Color(0xFFD4AF37).withAlpha(30), blurRadius: 18, offset: const Offset(0, 10)),
          ],
        ),
        child: child,
      );
    }

    return _DashedBorder(
      radius: 16,
      color: red,
      dash: 7,
      gap: 5,
      child: child,
    );
  }
}

class _DashedBorder extends StatelessWidget {
  const _DashedBorder({
    required this.child,
    required this.color,
    required this.radius,
    required this.dash,
    required this.gap,
  });

  final Widget child;
  final Color color;
  final double radius;
  final double dash;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(color: color, radius: radius, dash: dash, gap: gap),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.dash,
    required this.gap,
  });

  final Color color;
  final double radius;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final len = min(dash, metric.length - distance);
        final seg = metric.extractPath(distance, distance + len);
        canvas.drawPath(seg, paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.dash != dash ||
        oldDelegate.gap != gap;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    child: Icon(icon, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
