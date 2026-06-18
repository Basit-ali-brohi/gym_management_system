import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/form_dialog.dart';
import '../../core/providers.dart';
import '../../core/ui_kit.dart';
import '../../core/in_app_pdf.dart';
import '../../core/web_download_stub.dart' if (dart.library.html) '../../core/web_download_web.dart';
import '../../models/models.dart';
import '../auth/auth_controller.dart';

/// Parses a raw DB timestamp ("2026-05-15T05:04:06.000Z") into a clean,
/// human-readable label: "15 May 2026 • 05:04 AM".
String _fmtLogTime(String raw) {
  final d = DateTime.tryParse(raw);
  if (d == null) return raw;
  return DateFormat('dd MMM yyyy • hh:mm a').format(d);
}

final inventoryQueryProvider = StateProvider.autoDispose<_InventoryQuery>((ref) {
  return const _InventoryQuery(q: '', status: '', lowStock: false, from: '', to: '');
});

final inventorySortProvider = StateProvider.autoDispose<String>((ref) {
  return 'name_asc';
});

final productsControllerProvider =
    StateNotifierProvider.autoDispose<_ProductsController, AsyncValue<List<Product>>>((ref) {
  return _ProductsController(ref)..load();
});

final inventorySaleMemberSearchProvider =
    StateNotifierProvider.autoDispose<_InventorySaleMemberSearch, AsyncValue<List<Member>>>((ref) {
  return _InventorySaleMemberSearch(ref);
});

class _InventoryQuery {
  const _InventoryQuery({
    required this.q,
    required this.status,
    required this.lowStock,
    required this.from,
    required this.to,
  });

  final String q;
  final String status;
  final bool lowStock;
  final String from;
  final String to;

  Map<String, String> toQuery() {
    final map = <String, String>{'limit': '200'};
    if (q.trim().isNotEmpty) map['q'] = q.trim();
    if (status.trim().isNotEmpty) map['status'] = status.trim();
    if (lowStock) map['lowStock'] = 'true';
    if (from.trim().isNotEmpty) map['from'] = from.trim();
    if (to.trim().isNotEmpty) map['to'] = to.trim();
    return map;
  }

  _InventoryQuery copyWith({String? q, String? status, bool? lowStock, String? from, String? to}) {
    return _InventoryQuery(
      q: q ?? this.q,
      status: status ?? this.status,
      lowStock: lowStock ?? this.lowStock,
      from: from ?? this.from,
      to: to ?? this.to,
    );
  }
}

class _ProductsController extends StateNotifier<AsyncValue<List<Product>>> {
  _ProductsController(this.ref) : super(const AsyncValue.loading());

  final Ref ref;

  Future<void> load() async {
    state = const AsyncLoading<List<Product>>().copyWithPrevious(state);
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final q = ref.read(inventoryQueryProvider);
      final res = await api.getJson('/products', token: token, query: q.toQuery());
      final items = (res['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Product.fromJson(e.cast<String, dynamic>()))
          .toList();
      state = AsyncValue.data(items);
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error('products_load_failed', st);
    }
  }

  Future<void> addProduct({
    required String name,
    String? sku,
    required double price,
    required String status,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.postJson('/products', token: token, body: {
      'name': name.trim(),
      'sku': sku?.trim().isEmpty == true ? null : sku?.trim(),
      'price': price,
      'status': status,
    });
    await load();
  }

  Future<void> updateProduct({
    required int id,
    required String name,
    String? sku,
    required double price,
    required String status,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.patchJson('/products/$id', token: token, body: {
      'name': name.trim(),
      'sku': sku?.trim().isEmpty == true ? null : sku?.trim(),
      'price': price,
      'status': status,
    });
    await load();
  }

  Future<void> stockMove({
    required int productId,
    required int qty,
    required String movementType,
    String? reason,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.postJson('/stock/move', token: token, body: {
      'productId': productId,
      'qty': qty,
      'movementType': movementType,
      'reason': reason?.trim().isEmpty == true ? null : reason?.trim(),
    });
    await load();
  }

  Future<void> sellProduct({
    required int productId,
    required int memberId,
    required int qty,
    required String method,
    double? unitPrice,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.postJson('/products/sell', token: token, body: {
      'productId': productId,
      'memberId': memberId,
      'qty': qty,
      'method': method,
      ...?(unitPrice == null ? null : {'unitPrice': unitPrice}),
    });
    await load();
  }

  Future<void> deleteProduct(int productId) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.deleteJson('/products/$productId', token: token);
    await load();
  }
}

class _InventorySaleMemberSearch extends StateNotifier<AsyncValue<List<Member>>> {
  _InventorySaleMemberSearch(this.ref) : super(const AsyncValue.loading());

  final Ref ref;

  Future<void> load(String q) async {
    state = const AsyncLoading<List<Member>>().copyWithPrevious(state);
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final query = <String, String>{'limit': '30', 'status': 'active'};
      final trimmed = q.trim();
      if (trimmed.isNotEmpty) query['q'] = trimmed;
      final res = await api.getJson('/members', token: token, query: query);
      final items = (res['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Member.fromJson(e.cast<String, dynamic>()))
          .toList();
      state = AsyncValue.data(items);
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error('member_load_failed', st);
    }
  }
}

final stockMovementsProvider =
    FutureProvider.autoDispose.family<List<StockMovement>, int?>((ref, productId) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) throw ApiException('unauthorized');
  final api = ref.read(apiClientProvider);
  final query = <String, String>{'limit': '200'};
  if (productId != null) query['productId'] = productId.toString();
  final res = await api.getJson('/stock/movements', token: token, query: query);
  return (res['items'] as List<dynamic>? ?? [])
      .whereType<Map>()
      .map((e) => StockMovement.fromJson(e.cast<String, dynamic>()))
      .toList();
});

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String _csvEscape(String value) {
    final v = value.replaceAll('"', '""');
    return '"$v"';
  }

  Future<void> _exportProductsCsv(BuildContext context, List<Product> items) async {
    final now = DateTime.now();
    final date = DateFormat('yyyy-MM-dd').format(now);
    final name = 'inventory_$date.csv';
    final lines = <String>[
      ['id', 'name', 'sku', 'price', 'on_hand', 'status'].map(_csvEscape).join(','),
      ...items.map((p) {
        return [
          p.id.toString(),
          p.name,
          p.sku ?? '',
          p.price.toString(),
          p.onHand.toString(),
          p.status,
        ].map(_csvEscape).join(',');
      }),
    ];
    final bytes = utf8.encode('${lines.join('\r\n')}\r\n');
    final path = downloadBytes(fileName: name, bytes: bytes, mimeType: 'text/csv');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(path == null ? 'Exported' : 'Exported: $path')),
    );
  }

  Future<void> _openInventoryPdfActions(BuildContext context) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Inventory PDF'),
          content: const Text('Preview ya download?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runInventoryPdf(context, preview: true, today: today);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runInventoryPdf(context, preview: false, today: today);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runInventoryPdf(BuildContext context, {required bool preview, required String today}) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final bytes = await api.getBytes('/pdf/inventory.pdf', token: token);
      final name = 'inventory_$today.pdf';
      if (!context.mounted) return;
      await presentPdf(context, preview: preview, bytes: bytes, fileName: name, title: 'Inventory Report Preview');
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern();
    final money = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 0);
    final query = ref.watch(inventoryQueryProvider);
    final sort = ref.watch(inventorySortProvider);
    final itemsAsync = ref.watch(productsControllerProvider);
    final rawRoles = ref.watch(authControllerProvider).user?.roles ?? const <String>[];
    final roles = rawRoles
        .map((r) => r.trim().toLowerCase().replaceAll(' ', '_'))
        .where((r) => r.isNotEmpty)
        .toSet();
    final canDelete = roles.contains('owner') || roles.contains('admin') || roles.contains('super_admin');

    if (_searchCtrl.text != query.q && !_searchFocus.hasFocus) {
      _searchCtrl.text = query.q;
    }

    return DefaultTabController(
      length: 3,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) {
          return [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, c) {
                        final titleBlock = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Inventory', style: theme.textTheme.headlineSmall),
                            const SizedBox(height: 6),
                            Text(
                              'Manage products, supplements, and stock',
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        );
                        final searchField = TextField(
                          controller: _searchCtrl,
                          focusNode: _searchFocus,
                          decoration: const InputDecoration(
                            hintText: 'Search product, SKU, ...',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (v) {
                            ref.read(inventoryQueryProvider.notifier).state = query.copyWith(q: v);
                            _searchDebounce?.cancel();
                            _searchDebounce = Timer(const Duration(milliseconds: 350), () {
                              if (!mounted) return;
                              ref.read(productsControllerProvider.notifier).load();
                            });
                          },
                          onSubmitted: (_) {
                            _searchDebounce?.cancel();
                            ref.read(productsControllerProvider.notifier).load();
                          },
                        );
                        if (c.maxWidth < 600) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              titleBlock,
                              const SizedBox(height: 12),
                              searchField,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: titleBlock),
                            SizedBox(width: 360, child: searchField),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    TabBar(
                      dividerColor: Colors.transparent,
                      labelStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                      tabs: const [
                        Tab(text: 'Overview'),
                        Tab(text: 'Logs'),
                        Tab(text: 'Suppliers'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          children: [
                itemsAsync.when(
                  data: (rawItems) {
                    final items = [...rawItems];
                    if (sort == 'name_desc') {
                      items.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
                    } else if (sort == 'stock_desc') {
                      items.sort((a, b) => b.onHand.compareTo(a.onHand));
                    } else if (sort == 'stock_asc') {
                      items.sort((a, b) => a.onHand.compareTo(b.onHand));
                    } else {
                      items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                    }

                    final totalStoreValue =
                        items.fold<double>(0, (sum, p) => sum + (p.onHand.toDouble() * p.price));
                    final criticalCount = items.where((p) => p.onHand < 5 && p.status == 'active').length;
                    final activeSkuCount = items.where((p) => p.status == 'active').length;
                    final outOfStockCount = items.where((p) => p.onHand <= 0).length;

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        // ── Edge-to-edge 4-up metric grid ──────────────────
                        LayoutBuilder(
                          builder: (context, c) {
                            final tiles = <Widget>[
                              _MetricCard(
                                title: 'Total store value',
                                value: money.format(totalStoreValue),
                                subtitle: 'Current stock value',
                                icon: Icons.account_balance_wallet_outlined,
                                accent: theme.colorScheme.primary,
                              ),
                              _MetricCard(
                                title: 'Critical stock alerts',
                                value: '${number.format(criticalCount)} items',
                                subtitle: 'Requires immediate reorder',
                                icon: Icons.warning_amber_outlined,
                                accent: const Color(0xFFF59E0B),
                              ),
                              _MetricCard(
                                title: 'Active SKU count',
                                value: number.format(activeSkuCount),
                                subtitle: 'Spread across ${number.format(1)} zone',
                                icon: Icons.grid_view_outlined,
                                accent: theme.colorScheme.tertiary,
                              ),
                              _MetricCard(
                                title: 'Out of stock SKUs',
                                value: number.format(outOfStockCount),
                                subtitle: 'Zero on-hand units',
                                icon: Icons.remove_shopping_cart_outlined,
                                accent: const Color(0xFFE06C6C),
                              ),
                            ];
                            final cols = c.maxWidth >= 900
                                ? 4
                                : c.maxWidth >= 520
                                    ? 2
                                    : 1;
                            const gap = 12.0;
                            return Column(
                              children: [
                                for (var i = 0; i < tiles.length; i += cols)
                                  Padding(
                                    padding: EdgeInsets.only(bottom: i + cols < tiles.length ? gap : 0),
                                    child: IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          for (var j = 0; j < cols; j++) ...[
                                            if (j > 0) const SizedBox(width: gap),
                                            Expanded(
                                              child: (i + j) < tiles.length ? tiles[i + j] : const SizedBox.shrink(),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        // ── Single-line filter strip (controls locked to 40px) ──
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Builder(
                              builder: (context) {
                                final isDark = theme.brightness == Brightness.dark;
                                Widget dateBtn(String fallback, String value, ValueChanged<DateTime> onPick) {
                                  final isSet = value.trim().isNotEmpty;
                                  final accent = theme.colorScheme.primary;
                                  return SizedBox(
                                    height: 40,
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final parsed = DateTime.tryParse(value) ?? DateTime.now();
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: parsed,
                                          firstDate: DateTime(2000),
                                          lastDate: DateTime(2100),
                                        );
                                        if (picked == null) return;
                                        onPick(picked);
                                      },
                                      icon: Icon(Icons.calendar_today_outlined, size: 15,
                                          color: isSet ? accent : theme.colorScheme.onSurfaceVariant),
                                      label: Text(
                                        isSet ? value.trim() : fallback,
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          fontWeight: isSet ? FontWeight.w600 : FontWeight.w500,
                                          color: isSet ? accent : theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                        side: BorderSide(
                                          color: isSet
                                              ? accent.withAlpha(95)
                                              : (isDark ? Colors.white.withAlpha(33) : Colors.black.withAlpha(33)),
                                          width: 1,
                                        ),
                                        backgroundColor: isSet ? accent.withAlpha(isDark ? 30 : 22) : Colors.transparent,
                                      ),
                                    ),
                                  );
                                }

                                return Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 170,
                                      height: 40,
                                      child: DropdownButtonFormField<String>(
                                        initialValue: 'all',
                                        isDense: true,
                                        isExpanded: true,
                                        style: GoogleFonts.inter(fontSize: 13.5, color: theme.colorScheme.onSurface),
                                        decoration: appDenseInputDecoration(context),
                                        items: const [DropdownMenuItem(value: 'all', child: Text('All types'))],
                                        onChanged: null,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 170,
                                      height: 40,
                                      child: DropdownButtonFormField<String>(
                                        key: ValueKey(query.status),
                                        initialValue: query.status.isEmpty ? '' : query.status,
                                        isDense: true,
                                        isExpanded: true,
                                        style: GoogleFonts.inter(fontSize: 13.5, color: theme.colorScheme.onSurface),
                                        decoration: appDenseInputDecoration(context),
                                        items: const [
                                          DropdownMenuItem(value: '', child: Text('All Statuses')),
                                          DropdownMenuItem(value: 'active', child: Text('Active')),
                                          DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                                        ],
                                        onChanged: (v) {
                                          ref.read(inventoryQueryProvider.notifier).state = query.copyWith(status: v ?? '');
                                          ref.read(productsControllerProvider.notifier).load();
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      width: 180,
                                      height: 40,
                                      child: DropdownButtonFormField<String>(
                                        key: ValueKey(sort),
                                        initialValue: sort,
                                        isDense: true,
                                        isExpanded: true,
                                        style: GoogleFonts.inter(fontSize: 13.5, color: theme.colorScheme.onSurface),
                                        decoration: appDenseInputDecoration(context),
                                        items: const [
                                          DropdownMenuItem(value: 'name_asc', child: Text('Name A-Z')),
                                          DropdownMenuItem(value: 'name_desc', child: Text('Name Z-A')),
                                          DropdownMenuItem(value: 'stock_desc', child: Text('Stock high-low')),
                                          DropdownMenuItem(value: 'stock_asc', child: Text('Stock low-high')),
                                        ],
                                        onChanged: (v) =>
                                            ref.read(inventorySortProvider.notifier).state = v ?? 'name_asc',
                                      ),
                                    ),
                                    AppFilterPill(
                                      label: 'Low stock (<5)',
                                      icon: Icons.trending_down_rounded,
                                      selected: query.lowStock,
                                      accentOverride: const Color(0xFFF59E0B),
                                      onTap: () {
                                        ref.read(inventoryQueryProvider.notifier).state =
                                            query.copyWith(lowStock: !query.lowStock);
                                        ref.read(productsControllerProvider.notifier).load();
                                      },
                                    ),
                                    dateBtn('From', query.from, (d) {
                                      ref.read(inventoryQueryProvider.notifier).state =
                                          query.copyWith(from: DateFormat('yyyy-MM-dd').format(d));
                                      ref.read(productsControllerProvider.notifier).load();
                                    }),
                                    dateBtn('To', query.to, (d) {
                                      ref.read(inventoryQueryProvider.notifier).state =
                                          query.copyWith(to: DateFormat('yyyy-MM-dd').format(d));
                                      ref.read(productsControllerProvider.notifier).load();
                                    }),
                                    Text(
                                      'Showing ${number.format(items.length)}',
                                      style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                                    ),
                                    AppFilterPill(
                                      label: 'Clear',
                                      icon: Icons.close_rounded,
                                      selected: false,
                                      onTap: () {
                                        ref.read(inventoryQueryProvider.notifier).state =
                                            const _InventoryQuery(q: '', status: '', lowStock: false, from: '', to: '');
                                        _searchCtrl.clear();
                                        ref.read(productsControllerProvider.notifier).load();
                                      },
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, c) {
                            final productActions = <Widget>[
                              _HoverScaleButton(
                                child: OutlinedButton.icon(
                                  onPressed: items.isEmpty ? null : () => _exportProductsCsv(context, items),
                                  icon: const Icon(Icons.download_outlined),
                                  label: const Text('Export'),
                                ),
                              ),
                              IconButton(
                                tooltip: 'PDF',
                                onPressed: () => _openInventoryPdfActions(context),
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                              ),
                              _HoverScaleButton(
                                child: FilledButton.icon(
                                  onPressed: () => _openAddProduct(context, ref),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add Product'),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Refresh',
                                onPressed: () => ref.read(productsControllerProvider.notifier).load(),
                                icon: const Icon(Icons.refresh),
                              ),
                            ];
                            if (c.maxWidth < 560) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text('Products', style: theme.textTheme.titleLarge),
                                  const SizedBox(height: 10),
                                  Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: productActions),
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: Text('Products', style: theme.textTheme.titleLarge)),
                                for (var k = 0; k < productActions.length; k++) ...[
                                  if (k > 0) const SizedBox(width: 8),
                                  productActions[k],
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        if (items.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: 30,
                                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                    child: const Icon(Icons.inventory_2_outlined),
                                  ),
                                  const SizedBox(height: 16),
                                  Text('No products yet', style: theme.textTheme.titleMedium),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Add your first product to start tracking stock and alerts.',
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 14),
                                  FilledButton.icon(
                                    onPressed: () => _openAddProduct(context, ref),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Product'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Card(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                if (constraints.maxWidth >= 900) {
                                  final isDark = theme.brightness == Brightness.dark;
                                  return SingleChildScrollView(
                                    padding: const EdgeInsets.all(12),
                                    scrollDirection: Axis.horizontal,
                                    // Scoped Theme: Inter typography + faint dividers.
                                    child: Theme(
                                      data: theme.copyWith(
                                        dividerColor: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200,
                                        dataTableTheme: DataTableThemeData(
                                          dividerThickness: 1,
                                          headingTextStyle: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.3,
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                          dataTextStyle: GoogleFonts.inter(fontSize: 13.5, color: theme.colorScheme.onSurface),
                                          headingRowColor: WidgetStatePropertyAll(
                                            isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(5),
                                          ),
                                        ),
                                      ),
                                      child: DataTable(
                                      headingRowHeight: 48,
                                      dataRowMinHeight: 52,
                                      dataRowMaxHeight: 58,
                                      columns: const [
                                        DataColumn(label: Text('Name')),
                                        DataColumn(label: Text('SKU')),
                                        DataColumn(label: Text('Price')),
                                        DataColumn(label: Text('On-hand')),
                                        DataColumn(label: Text('Status')),
                                        DataColumn(label: Text('Action')),
                                      ],
                                      rows: [
                                        for (final p in items)
                                          DataRow(
                                            color: p.onHand < 5
                                                ? WidgetStateProperty.resolveWith<Color?>(
                                                    (_) => theme.colorScheme.error.withValues(alpha: 0.08),
                                                  )
                                                : null,
                                            cells: [
                                              DataCell(Text(p.name)),
                                              // SKU in tabular Inter for code alignment.
                                              DataCell(Text(
                                                p.sku ?? '-',
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  fontFeatures: const [FontFeature.tabularFigures()],
                                                  color: theme.colorScheme.onSurfaceVariant,
                                                ),
                                              )),
                                              DataCell(Text(
                                                number.format(p.price),
                                                style: GoogleFonts.inter(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w600,
                                                  fontFeatures: const [FontFeature.tabularFigures()],
                                                ),
                                              )),
                                              DataCell(Text(
                                                p.onHand.toString(),
                                                style: GoogleFonts.inter(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w600,
                                                  fontFeatures: const [FontFeature.tabularFigures()],
                                                ),
                                              )),
                                              DataCell(_StatusChip(status: p.status, onHand: p.onHand)),
                                              DataCell(
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    // Two high-frequency read actions exposed.
                                                    AppTableActionButton(
                                                      icon: Icons.visibility_outlined,
                                                      tooltip: 'View',
                                                      onPressed: () => _openViewProduct(context, p),
                                                    ),
                                                    const SizedBox(width: 2),
                                                    AppTableActionButton(
                                                      icon: Icons.edit_outlined,
                                                      tooltip: 'Edit',
                                                      onPressed: () => _openEditProduct(context, ref, p),
                                                    ),
                                                    const SizedBox(width: 2),
                                                    // The rest live in a clean overflow menu.
                                                    _ProductActionsMenu(
                                                      canDelete: canDelete,
                                                      onStockMove: () => _openStockMove(context, ref, p),
                                                      onSell: () => _openSellProduct(context, ref, p),
                                                      onMovements: () => _openMovements(context, ref, p.id, p.name),
                                                      onDelete: () => _confirmDeleteProduct(context, ref, p),
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
                                }

                                return ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: items.length,
                                  separatorBuilder: (context, _) => const Divider(height: 1),
                                  itemBuilder: (context, i) {
                                    final p = items[i];
                                    final low = p.onHand < 5;
                                    final glow = theme.colorScheme.error;
                                    return DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        border: low ? Border.all(color: glow, width: 1.2) : null,
                                        boxShadow: low
                                            ? [
                                                BoxShadow(
                                                  color: glow.withValues(alpha: 0.24),
                                                  blurRadius: 18,
                                                  spreadRadius: 1,
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Card(
                                        margin: EdgeInsets.zero,
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(14, 10, 4, 2),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(Icons.inventory_2_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      p.name,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  _StatusChip(status: p.status, onHand: p.onHand),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'On-hand: ${p.onHand}  •  Price ${number.format(p.price)}',
                                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                              ),
                                              Row(
                                                children: [
                                                  IconButton(
                                                    tooltip: 'Sell',
                                                    onPressed: () => _openSellProduct(context, ref, p),
                                                    icon: const Icon(Icons.point_of_sale),
                                                  ),
                                                  IconButton(
                                                    tooltip: 'View',
                                                    onPressed: () => _openViewProduct(context, p),
                                                    icon: const Icon(Icons.visibility),
                                                  ),
                                                  const Spacer(),
                                                  IconButton(
                                                    tooltip: 'Edit',
                                                    onPressed: () => _openEditProduct(context, ref, p),
                                                    icon: const Icon(Icons.edit_outlined),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                  error: (e, _) => Center(child: Text(e.toString())),
                  loading: () => const Center(child: CircularProgressIndicator()),
                ),
                _InventoryLogsTab(number: number),
                const _SuppliersTab(),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddProduct(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final skuCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '0');
    String status = 'active';

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.inventory_2_outlined,
      title: 'Add Product',
      subtitle: 'Manage product details and stock',
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final twoCol = constraints.maxWidth >= 680;
              final fieldWidth = twoCol ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;

              Widget field(Widget child) => SizedBox(width: fieldWidth, child: child);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Product Details', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      field(
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(labelText: 'Product Name'),
                        ),
                      ),
                      field(
                        TextField(
                          controller: skuCtrl,
                          decoration: const InputDecoration(labelText: 'SKU / Part Number'),
                        ),
                      ),
                      field(
                        DropdownButtonFormField<String>(
                          key: ValueKey(status),
                          initialValue: status,
                          decoration: const InputDecoration(labelText: 'Status'),
                          items: const [
                            DropdownMenuItem(value: 'active', child: Text('Active')),
                            DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                          ],
                          onChanged: (v) => setModalState(() => status = v ?? 'active'),
                        ),
                      ),
                      field(
                        TextField(
                          controller: priceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Price'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () async {
            final name = nameCtrl.text.trim();
            final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name required')));
              return;
            }
            try {
              await ref.read(productsControllerProvider.notifier).addProduct(
                    name: name,
                    sku: skuCtrl.text,
                    price: price,
                    status: status,
                  );
              if (!context.mounted) return;
              Navigator.of(context, rootNavigator: true).maybePop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product added')));
            } on ApiException catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
            }
          },
          child: const Text('Save'),
        ),
      ],
    );

    nameCtrl.dispose();
    skuCtrl.dispose();
    priceCtrl.dispose();
  }

  void _openViewProduct(BuildContext context, Product p) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(p.name),
          content: Text(
            [
              if (p.sku != null) 'SKU: ${p.sku}',
              'Price: ${p.price}',
              'On-hand: ${p.onHand}',
              'Status: ${p.status}',
            ].join('\n'),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        );
      },
    );
  }

  Future<void> _openEditProduct(BuildContext context, WidgetRef ref, Product p) async {
    final nameCtrl = TextEditingController(text: p.name);
    final skuCtrl = TextEditingController(text: p.sku ?? '');
    final priceCtrl = TextEditingController(text: p.price.toString());
    var status = p.status;

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.edit_outlined,
      title: 'Edit Product',
      subtitle: p.name,
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final twoCol = constraints.maxWidth >= 680;
              final fieldWidth = twoCol ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
              Widget field(Widget child) => SizedBox(width: fieldWidth, child: child);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Product Details', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      field(
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(labelText: 'Product Name'),
                        ),
                      ),
                      field(
                        TextField(
                          controller: skuCtrl,
                          decoration: const InputDecoration(labelText: 'SKU / Part Number'),
                        ),
                      ),
                      field(
                        DropdownButtonFormField<String>(
                          key: ValueKey(status),
                          initialValue: status,
                          decoration: const InputDecoration(labelText: 'Status'),
                          items: const [
                            DropdownMenuItem(value: 'active', child: Text('Active')),
                            DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                          ],
                          onChanged: (v) => setModalState(() => status = v ?? 'active'),
                        ),
                      ),
                      field(
                        TextField(
                          controller: priceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Price'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () async {
            final name = nameCtrl.text.trim();
            final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name required')));
              return;
            }
            try {
              await ref.read(productsControllerProvider.notifier).updateProduct(
                    id: p.id,
                    name: name,
                    sku: skuCtrl.text,
                    price: price,
                    status: status,
                  );
              if (!context.mounted) return;
              Navigator.of(context, rootNavigator: true).maybePop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated')));
            } on ApiException catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
            }
          },
          child: const Text('Save'),
        ),
      ],
    );

    nameCtrl.dispose();
    skuCtrl.dispose();
    priceCtrl.dispose();
  }

  Future<void> _confirmDeleteProduct(BuildContext context, WidgetRef ref, Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Deactivate product?'),
          content: Text('Deactivate ${p.name}?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Deactivate')),
          ],
        );
      },
    );
    if (ok != true) return;
    try {
      await ref.read(productsControllerProvider.notifier).deleteProduct(p.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Deactivated')));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
    }
  }

  Future<void> _openStockMove(BuildContext context, WidgetRef ref, Product product) async {
    final qtyCtrl = TextEditingController(text: '1');
    final reasonCtrl = TextEditingController();
    String movementType = 'in';

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.swap_vert,
      title: 'Stock & Pricing',
      subtitle: product.name,
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final twoCol = constraints.maxWidth >= 680;
              final fieldWidth = twoCol ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
              Widget field(Widget child) => SizedBox(width: fieldWidth, child: child);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Stock move', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      field(
                        DropdownButtonFormField<String>(
                          key: ValueKey(movementType),
                          initialValue: movementType,
                          decoration: const InputDecoration(labelText: 'Type'),
                          items: const [
                            DropdownMenuItem(value: 'in', child: Text('Stock In')),
                            DropdownMenuItem(value: 'out', child: Text('Stock Out')),
                          ],
                          onChanged: (v) => setModalState(() => movementType = v ?? 'in'),
                        ),
                      ),
                      field(
                        TextField(
                          controller: qtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Quantity'),
                        ),
                      ),
                      SizedBox(
                        width: constraints.maxWidth,
                        child: TextField(
                          controller: reasonCtrl,
                          decoration: const InputDecoration(labelText: 'Reason (optional)'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () async {
            final qty = int.tryParse(qtyCtrl.text.trim());
            if (qty == null || qty <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid quantity')));
              return;
            }
            try {
              await ref.read(productsControllerProvider.notifier).stockMove(
                    productId: product.id,
                    qty: qty,
                    movementType: movementType,
                    reason: reasonCtrl.text,
                  );
              if (!context.mounted) return;
              Navigator.of(context, rootNavigator: true).maybePop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock updated')));
            } on ApiException catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
            }
          },
          child: const Text('Save'),
        ),
      ],
    );

    qtyCtrl.dispose();
    reasonCtrl.dispose();
  }

  Future<void> _openSellProduct(BuildContext context, WidgetRef ref, Product product) async {
    final qtyCtrl = TextEditingController(text: '1');
    final memberSearchCtrl = TextEditingController();
    int? memberId;
    String method = 'cash';

    ref.read(inventorySaleMemberSearchProvider.notifier).load('');

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.point_of_sale,
      title: 'Sell Product',
      subtitle: product.name,
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return Consumer(
            builder: (context, r, _) {
              final membersAsync = r.watch(inventorySaleMemberSearchProvider);
              final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
              final total = qty <= 0 ? 0 : (qty * product.price);

              return LayoutBuilder(
                builder: (context, constraints) {
                  final twoCol = constraints.maxWidth >= 680;
                  final fieldWidth = twoCol ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
                  Widget field(Widget child) => SizedBox(width: fieldWidth, child: child);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sale details', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          field(
                            TextField(
                              controller: memberSearchCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Member search',
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (v) => r.read(inventorySaleMemberSearchProvider.notifier).load(v),
                            ),
                          ),
                          field(
                            membersAsync.when(
                              data: (items) {
                                final ids = items.map((m) => m.id).toSet();
                                if (memberId != null && !ids.contains(memberId)) memberId = null;
                                return DropdownButtonFormField<int>(
                                  key: ValueKey('${memberId ?? ''}-${items.length}'),
                                  initialValue: memberId,
                                  decoration: const InputDecoration(labelText: 'Member'),
                                  items: [
                                    for (final m in items)
                                      DropdownMenuItem(
                                        value: m.id,
                                        child: Text('${m.fullName} (${m.memberCode})'),
                                      ),
                                  ],
                                  onChanged: (v) => setModalState(() => memberId = v),
                                );
                              },
                              error: (e, _) => Text('Failed: $e'),
                              loading: () => const LinearProgressIndicator(),
                            ),
                          ),
                          field(
                            TextField(
                              controller: qtyCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Qty'),
                              onChanged: (_) => setModalState(() {}),
                            ),
                          ),
                          field(
                            DropdownButtonFormField<String>(
                              key: ValueKey(method),
                              initialValue: method,
                              decoration: const InputDecoration(labelText: 'Payment method'),
                              items: const [
                                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                                DropdownMenuItem(value: 'card', child: Text('Card')),
                                DropdownMenuItem(value: 'bank', child: Text('Bank')),
                                DropdownMenuItem(value: 'online', child: Text('Online')),
                              ],
                              onChanged: (v) => setModalState(() => method = v ?? 'cash'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Unit price: ${product.price} • Total: ${total.toStringAsFixed(2)}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              Text(
                                'On-hand: ${product.onHand}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () async {
            final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
            if (memberId == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select member')));
              return;
            }
            if (qty <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Qty must be > 0')));
              return;
            }
            try {
              await ref.read(productsControllerProvider.notifier).sellProduct(
                    productId: product.id,
                    memberId: memberId!,
                    qty: qty,
                    method: method,
                  );
              if (!context.mounted) return;
              Navigator.of(context, rootNavigator: true).maybePop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sale recorded')));
            } on ApiException catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
            }
          },
          child: const Text('Save'),
        ),
      ],
    );

    qtyCtrl.dispose();
    memberSearchCtrl.dispose();
  }

  Future<void> _openMovements(BuildContext context, WidgetRef ref, int productId, String title) async {
    final dt = DateFormat('yyyy-MM-dd HH:mm');
    String fmt(String raw) {
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) return raw;
      return dt.format(parsed);
    }

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.history,
      title: 'Movements',
      subtitle: title,
      body: SizedBox(
        height: 380,
        child: Consumer(
          builder: (context, ref, _) {
            final async = ref.watch(stockMovementsProvider(productId));
            return async.when(
              data: (items) {
                if (items.isEmpty) return const Center(child: Text('No movements'));
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (context, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final m = items[i];
                    final sign = m.movementType == 'in' ? '+' : '-';
                    return ListTile(
                      leading: Icon(m.movementType == 'in' ? Icons.call_received : Icons.call_made),
                      title: Text('$sign${m.qty} • ${fmt(m.createdAt)}'),
                      subtitle: Text(m.reason ?? '-'),
                    );
                  },
                );
              },
              error: (e, _) => Center(child: Text(e.toString())),
              loading: () => const Center(child: CircularProgressIndicator()),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _InventoryLogsTab extends ConsumerWidget {
  const _InventoryLogsTab({required this.number});

  final NumberFormat number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final logsAsync = ref.watch(stockMovementsProvider(null));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: logsAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const _EmptyState(
              title: 'No stock logs',
              subtitle: 'Stock in/out entries will appear here.',
              icon: Icons.history,
            );
          }
          return Card(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (context, _) => Divider(height: 1, color: AppTheme.borderSubtle),
              itemBuilder: (context, i) {
                final m = items[i];
                final isIn = m.movementType == 'in';
                final sign = isIn ? '+' : '-';
                final color = isIn ? theme.colorScheme.tertiary : theme.colorScheme.error;
                // Parse the raw DB timestamp into "15 May 2026 • 05:04 AM".
                final when = _fmtLogTime(m.createdAt);
                final reason = (m.reason == null || m.reason!.trim().isEmpty) ? null : m.reason!.trim();
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withAlpha(28),
                    child: Icon(isIn ? Icons.south_west_rounded : Icons.north_east_rounded, color: color, size: 18),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          m.productName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Signed quantity badge in tabular Inter.
                      Text(
                        '$sign${number.format(m.qty)}',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      reason == null ? when : '$when • $reason',
                      style: GoogleFonts.inter(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                );
              },
            ),
          );
        },
        error: (e, _) => Center(child: Text(e.toString())),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _SuppliersTab extends StatelessWidget {
  const _SuppliersTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 360),
        child: AppDashedPanel(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary.withAlpha(26),
                      border: Border.all(color: theme.colorScheme.primary.withAlpha(60), width: 0.8),
                    ),
                    child: Icon(Icons.local_shipping_outlined, size: 27, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'SUPPLIERS',
                    style: AppTypography.sectionHeader(color: theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Suppliers module UI is ready. Supplier CRUD can be added next.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
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

/// Overflow menu for low-frequency product operations.
/// Keeps the row clean: View + Edit stay exposed; Stock In/Out, Sell (POS),
/// Ledger history, and Delete live behind a single more_vert button.
class _ProductActionsMenu extends StatelessWidget {
  const _ProductActionsMenu({
    required this.canDelete,
    required this.onStockMove,
    required this.onSell,
    required this.onMovements,
    required this.onDelete,
  });

  final bool canDelete;
  final VoidCallback onStockMove;
  final VoidCallback onSell;
  final VoidCallback onMovements;
  final VoidCallback onDelete;

  static const Color _mutedRed = Color(0xFFE06C6C);

  PopupMenuItem<String> _item(BuildContext context, String value, IconData icon, String label, {bool danger = false}) {
    final theme = Theme.of(context);
    final color = danger ? _mutedRed : theme.colorScheme.onSurface;
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 18, color: danger ? _mutedRed : theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      position: PopupMenuPosition.under,
      elevation: 10,
      color: isDark ? const Color(0xFF1E1E24) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.white.withAlpha(22) : Colors.black.withAlpha(16),
          width: 0.8,
        ),
      ),
      icon: Icon(Icons.more_vert, size: 18, color: theme.colorScheme.onSurfaceVariant),
      onSelected: (v) {
        switch (v) {
          case 'stock':
            onStockMove();
            break;
          case 'sell':
            onSell();
            break;
          case 'ledger':
            onMovements();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      itemBuilder: (context) => [
        _item(context, 'stock', Icons.swap_vert, 'Adjust stock'),
        _item(context, 'sell', Icons.point_of_sale_outlined, 'POS sale'),
        _item(context, 'ledger', Icons.history, 'Ledger history'),
        if (canDelete) const PopupMenuDivider(),
        if (canDelete) _item(context, 'delete', Icons.delete_outline, 'Deactivate', danger: true),
      ],
    );
  }
}

/// Flex inventory metric tile — fills its parent (no fixed width) so 4 tiles
/// span edge-to-edge. Figure rendered in Bebas Neue.
class _MetricCard extends StatefulWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.accent,
    this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color accent;
  final IconData? icon;

  @override
  State<_MetricCard> createState() => _MetricCardState();
}

class _MetricCardState extends State<_MetricCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark ? AppTheme.charcoal : theme.colorScheme.surface,
          border: Border.all(
            color: _hover
                ? widget.accent.withAlpha(90)
                : (isDark ? AppTheme.borderSubtle : theme.colorScheme.outlineVariant),
            width: _hover ? 1.0 : 0.8,
          ),
          boxShadow: _hover
              ? [BoxShadow(color: widget.accent.withAlpha(40), blurRadius: 26, offset: const Offset(0, 12))]
              : [BoxShadow(color: Colors.black.withAlpha(isDark ? 55 : 12), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: widget.accent.withAlpha(28),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: widget.accent.withAlpha(60), width: 0.8),
                ),
                child: Icon(widget.icon ?? Icons.inventory_2_outlined, color: widget.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.value,
                        maxLines: 1,
                        style: theme.textTheme.headlineSmall?.copyWith(color: widget.accent),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Flat stock-status pill — Inter, colour-coded: low → amber, active →
/// emerald, inactive → muted grey.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.onHand});

  final String status;
  final int onHand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final low = onHand < 5;
    final isActive = status == 'active';
    final accent = low
        ? const Color(0xFFF59E0B)
        : isActive
            ? theme.colorScheme.tertiary
            : theme.colorScheme.onSurfaceVariant;
    final label = low ? 'low' : status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withAlpha(low ? 110 : 70), width: low ? 1.0 : 0.8),
        boxShadow: low ? AppTheme.neonGlow(accent, blur: 8) : const [],
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: accent, letterSpacing: 0.1),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
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
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverScaleButton extends StatefulWidget {
  const _HoverScaleButton({required this.child});

  final Widget child;

  @override
  State<_HoverScaleButton> createState() => _HoverScaleButtonState();
}

class _HoverScaleButtonState extends State<_HoverScaleButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        scale: _hover ? 1.03 : 1,
        child: widget.child,
      ),
    );
  }
}
