import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../models/models.dart';
import '../auth/auth_controller.dart';

final settingsProvider = FutureProvider.autoDispose<GymSettings>((ref) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) throw ApiException('unauthorized');
  final api = ref.read(apiClientProvider);
  final res = await api.getJson('/settings', token: token);
  return GymSettings.fromJson(res);
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _gymNameCtrl = TextEditingController(text: 'Gym');
  final _currencyCtrl = TextEditingController(text: 'PKR');
  final _taxCtrl = TextEditingController(text: '5');
  final _addressCtrl = TextEditingController();
  final _logoUrlCtrl = TextEditingController();

  bool _enableSound = true;
  bool _enableAnimations = true;
  bool _hydrated = false;

  @override
  void dispose() {
    _gymNameCtrl.dispose();
    _currencyCtrl.dispose();
    _taxCtrl.dispose();
    _addressCtrl.dispose();
    _logoUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(settingsProvider);
    final mode = ref.watch(themeModeProvider);
    final isDark = mode == ThemeMode.dark;

    final s = settingsAsync.valueOrNull;
    if (!_hydrated && s != null) {
      _hydrated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          if (s.gymName != null && s.gymName!.trim().isNotEmpty) _gymNameCtrl.text = s.gymName!.trim();
          _currencyCtrl.text = s.currency;
          _taxCtrl.text = s.defaultTaxPercent.toStringAsFixed(0);
          _enableSound = s.enableSounds;
          _enableAnimations = s.enableAnimations;
          _addressCtrl.text = s.address ?? '';
          _logoUrlCtrl.text = s.logoUrl ?? '';
        });
      });
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Settings', style: theme.textTheme.headlineSmall)),
                  FilledButton.icon(
                    onPressed: () => _save(context),
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(
                    title: 'Theme',
                    value: isDark ? 'Dark' : 'Light',
                    subtitle: 'Active mode',
                    icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  ),
                  _MetricCard(
                    title: 'Currency',
                    value: _currencyCtrl.text.trim().isEmpty ? 'PKR' : _currencyCtrl.text.trim(),
                    subtitle: 'Billing currency',
                    icon: Icons.currency_exchange,
                  ),
                  _MetricCard(
                    title: 'Tax %',
                    value: _taxCtrl.text.trim().isEmpty ? '0' : _taxCtrl.text.trim(),
                    subtitle: 'Default tax',
                    icon: Icons.percent,
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              settingsAsync.when(
                data: (_) => const SizedBox.shrink(),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(e.toString()),
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gym Profile', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _gymNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Gym Name',
                          prefixIcon: Icon(Icons.fitness_center),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _currencyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                          prefixIcon: Icon(Icons.currency_exchange),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _addressCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Address',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _logoUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Logo URL',
                          prefixIcon: Icon(Icons.image_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Billing', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _taxCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Default Tax %',
                          prefixIcon: Icon(Icons.percent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      value: isDark,
                      onChanged: (v) {
                        ref.read(themeModeProvider.notifier).setMode(v ? ThemeMode.dark : ThemeMode.light);
                      },
                      title: const Text('Dark Theme'),
                      subtitle: const Text('Toggle between Obsidian and White theme'),
                      secondary: const Icon(Icons.dark_mode),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _enableSound,
                      onChanged: (v) => setState(() => _enableSound = v),
                      title: const Text('Enable Sounds'),
                      subtitle: const Text('Access denied / success sounds'),
                      secondary: const Icon(Icons.volume_up),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _enableAnimations,
                      onChanged: (v) => setState(() => _enableAnimations = v),
                      title: const Text('Enable Animations'),
                      subtitle: const Text('Smooth fade transitions'),
                      secondary: const Icon(Icons.animation),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _save(BuildContext context) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final tax = double.tryParse(_taxCtrl.text.trim()) ?? 0;
      final res = await api.putJson('/settings', token: token, body: {
        'gymName': _gymNameCtrl.text.trim().isEmpty ? null : _gymNameCtrl.text.trim(),
        'currency': _currencyCtrl.text.trim().isEmpty ? 'PKR' : _currencyCtrl.text.trim(),
        'defaultTaxPercent': tax,
        'enableSounds': _enableSound,
        'enableAnimations': _enableAnimations,
        'address': _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'logoUrl': _logoUrlCtrl.text.trim().isEmpty ? null : _logoUrlCtrl.text.trim(),
      });
      ref.invalidate(settingsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved: ${res['currency']} • Tax ${res['defaultTaxPercent']}%')));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
    }
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
}
