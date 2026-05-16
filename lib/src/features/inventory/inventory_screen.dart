import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/form_dialog.dart';
import '../../core/providers.dart';
import '../../core/web_download_stub.dart' if (dart.library.html) '../../core/web_download_web.dart';
import '../../models/models.dart';
import '../auth/auth_controller.dart';

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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Inventory', style: theme.textTheme.headlineSmall),
                              const SizedBox(height: 6),
                              Text(
                                'Manage products, supplements, and stock',
                                style:
                                    theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 360,
                          child: TextField(
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
                          ),
                        ),
                      ],
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

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _MetricCard(
                              title: 'Total store value',
                              value: money.format(totalStoreValue),
                              subtitle: 'Current stock value',
                              icon: Icons.account_balance_wallet_outlined,
                            ),
                            _MetricCard(
                              title: 'Critical stock alerts',
                              value: '${number.format(criticalCount)} items',
                              subtitle: 'Requires immediate reorder',
                              icon: Icons.warning_amber_outlined,
                            ),
                            _MetricCard(
                              title: 'Active SKU count',
                              value: number.format(activeSkuCount),
                              subtitle: 'Spread across ${number.format(1)} zone',
                              icon: Icons.grid_view_outlined,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: 180,
                                  child: DropdownButtonFormField<String>(
                                    decoration: const InputDecoration(labelText: 'All types'),
                                    initialValue: 'all',
                                    items: const [
                                      DropdownMenuItem(value: 'all', child: Text('All types')),
                                    ],
                                    onChanged: null,
                                  ),
                                ),
                                SizedBox(
                                  width: 190,
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey(query.status),
                                    decoration: const InputDecoration(labelText: 'All Statuses'),
                                    initialValue: query.status.isEmpty ? null : query.status,
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
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey(sort),
                                    decoration: const InputDecoration(labelText: 'Sort'),
                                    initialValue: sort,
                                    items: const [
                                      DropdownMenuItem(value: 'name_asc', child: Text('Name A–Z')),
                                      DropdownMenuItem(value: 'name_desc', child: Text('Name Z–A')),
                                      DropdownMenuItem(value: 'stock_desc', child: Text('Stock high–low')),
                                      DropdownMenuItem(value: 'stock_asc', child: Text('Stock low–high')),
                                    ],
                                    onChanged: (v) =>
                                        ref.read(inventorySortProvider.notifier).state = v ?? 'name_asc',
                                  ),
                                ),
                                Text(
                                  'Showing ${number.format(items.length)} of ${number.format(items.length)}',
                                  style:
                                      theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                                OutlinedButton(
                                  onPressed: () {
                                    ref.read(inventoryQueryProvider.notifier).state =
                                        const _InventoryQuery(q: '', status: '', lowStock: false, from: '', to: '');
                                    ref.read(productsControllerProvider.notifier).load();
                                  },
                                  child: const Text('Clear'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    DateTime initial = DateTime.now();
                                    final parsed = DateTime.tryParse(query.from);
                                    if (parsed != null) initial = parsed;
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: initial,
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (picked == null) return;
                                    ref.read(inventoryQueryProvider.notifier).state =
                                        query.copyWith(from: DateFormat('yyyy-MM-dd').format(picked));
                                    ref.read(productsControllerProvider.notifier).load();
                                  },
                                  icon: const Icon(Icons.date_range),
                                  label: Text(query.from.trim().isEmpty ? 'From' : query.from.trim()),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    DateTime initial = DateTime.now();
                                    final parsed = DateTime.tryParse(query.to);
                                    if (parsed != null) initial = parsed;
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: initial,
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (picked == null) return;
                                    ref.read(inventoryQueryProvider.notifier).state =
                                        query.copyWith(to: DateFormat('yyyy-MM-dd').format(picked));
                                    ref.read(productsControllerProvider.notifier).load();
                                  },
                                  icon: const Icon(Icons.date_range),
                                  label: Text(query.to.trim().isEmpty ? 'To' : query.to.trim()),
                                ),
                                const SizedBox(width: 6),
                                FilterChip(
                                  label: const Text('Low stock (<5)'),
                                  selected: query.lowStock,
                                  onSelected: (v) {
                                    ref.read(inventoryQueryProvider.notifier).state = query.copyWith(lowStock: v);
                                    ref.read(productsControllerProvider.notifier).load();
                                  },
                                ),
                                FilledButton(
                                  onPressed: () => ref.read(productsControllerProvider.notifier).load(),
                                  child: const Text('Apply'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: Text('Products', style: theme.textTheme.titleLarge)),
                            _HoverScaleButton(
                              child: OutlinedButton.icon(
                                onPressed: items.isEmpty ? null : () => _exportProductsCsv(context, items),
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Export'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              tooltip: 'PDF',
                              onPressed: () => _openInventoryPdfActions(context),
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                            ),
                            const SizedBox(width: 6),
                            _HoverScaleButton(
                              child: FilledButton.icon(
                                onPressed: () => _openAddProduct(context, ref),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Product'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Refresh',
                              onPressed: () => ref.read(productsControllerProvider.notifier).load(),
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
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
                                  return SingleChildScrollView(
                                    padding: const EdgeInsets.all(12),
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
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
                                              DataCell(Text(p.sku ?? '-')),
                                              DataCell(Text(number.format(p.price))),
                                              DataCell(Text(p.onHand.toString())),
                                              DataCell(_StatusChip(status: p.status, onHand: p.onHand)),
                                              DataCell(
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      tooltip: 'View',
                                                      onPressed: () => _openViewProduct(context, p),
                                                      icon: const Icon(Icons.visibility),
                                                    ),
                                                    IconButton(
                                                      tooltip: 'Edit',
                                                      onPressed: () => _openEditProduct(context, ref, p),
                                                      icon: const Icon(Icons.edit_outlined),
                                                    ),
                                                    IconButton(
                                                      tooltip: 'Stock In/Out',
                                                      onPressed: () => _openStockMove(context, ref, p),
                                                      icon: const Icon(Icons.swap_vert),
                                                    ),
                                                    IconButton(
                                                      tooltip: 'Sell',
                                                      onPressed: () => _openSellProduct(context, ref, p),
                                                      icon: const Icon(Icons.point_of_sale),
                                                    ),
                                                    IconButton(
                                                      tooltip: 'Movements',
                                                      onPressed: () => _openMovements(context, ref, p.id, p.name),
                                                      icon: const Icon(Icons.history),
                                                    ),
                                                    if (canDelete)
                                                      IconButton(
                                                        tooltip: 'Deactivate',
                                                        onPressed: () => _confirmDeleteProduct(context, ref, p),
                                                        icon: const Icon(Icons.delete_outline),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
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
                                        child: ListTile(
                                          leading: const Icon(Icons.inventory_2_outlined),
                                          title: Text(p.name),
                                          subtitle: Text('On-hand: ${p.onHand} • Price: ${number.format(p.price)}'),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _StatusChip(status: p.status, onHand: p.onHand),
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
                                              IconButton(
                                                tooltip: 'Edit',
                                                onPressed: () => _openEditProduct(context, ref, p),
                                                icon: const Icon(Icons.edit_outlined),
                                              ),
                                            ],
                                          ),
                                          onTap: () => _openViewProduct(context, p),
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
              separatorBuilder: (context, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final m = items[i];
                final sign = m.movementType == 'in' ? '+' : '-';
                final color = m.movementType == 'in' ? theme.colorScheme.tertiary : theme.colorScheme.error;
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withAlpha(24),
                    child: Icon(m.movementType == 'in' ? Icons.call_received : Icons.call_made, color: color),
                  ),
                  title: Text('${m.productName} • $sign${number.format(m.qty)}'),
                  subtitle: Text('${m.createdAt} ${m.reason == null ? '' : '• ${m.reason}'}'),
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
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: _EmptyState(
        title: 'Suppliers',
        subtitle: 'Suppliers module UI is ready. Supplier CRUD can be added next.',
        icon: Icons.groups_outlined,
      ),
    );
  }
}

class _MetricCard extends StatefulWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData? icon;

  @override
  State<_MetricCard> createState() => _MetricCardState();
}

class _MetricCardState extends State<_MetricCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 260,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          scale: _hover ? 1.015 : 1,
          child: Card(
            elevation: _hover ? 6 : 2,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: _hover
                    ? [
                        BoxShadow(
                          color: theme.colorScheme.primary.withAlpha(28),
                          blurRadius: 22,
                          offset: const Offset(0, 12),
                        )
                      ]
                    : const [],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.icon != null)
                      Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(widget.icon, color: theme.colorScheme.onPrimaryContainer),
                      ),
                    if (widget.icon != null) const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          Text(widget.value, style: theme.textTheme.headlineSmall),
                          const SizedBox(height: 2),
                          Text(widget.subtitle, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.onHand});

  final String status;
  final int onHand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final low = onHand < 5;
    final isActive = status == 'active';
    final glow = theme.colorScheme.primary;
    final bg = low
        ? glow.withValues(alpha: 0.18)
        : isActive
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest;
    final fg = low
        ? glow
        : isActive
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant;
    final label = low ? 'low' : status;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: low ? Border.all(color: glow, width: 1.2) : null,
        boxShadow: low
            ? [
                BoxShadow(
                  color: glow.withValues(alpha: 0.28),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Chip(
        label: Text(label),
        backgroundColor: bg,
        labelStyle: theme.textTheme.labelMedium?.copyWith(color: fg),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide.none,
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
