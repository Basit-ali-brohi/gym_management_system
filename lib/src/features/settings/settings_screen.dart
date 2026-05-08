import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/web_download_stub.dart' if (dart.library.html) '../../core/web_download_web.dart';
import '../../core/web_image_picker_stub.dart' if (dart.library.html) '../../core/web_image_picker_web.dart';
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
  final _websiteCtrl = TextEditingController();
  final _facebookCtrl = TextEditingController();
  final _instagramCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();

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
    _websiteCtrl.dispose();
    _facebookCtrl.dispose();
    _instagramCtrl.dispose();
    _whatsappCtrl.dispose();
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
          _websiteCtrl.text = s.websiteUrl ?? '';
          _facebookCtrl.text = s.facebookUrl ?? '';
          _instagramCtrl.text = s.instagramUrl ?? '';
          _whatsappCtrl.text = s.whatsapp ?? '';
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
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'PDF',
                    onPressed: () => _openSettingsPdfActions(context),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
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
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 520,
                            child: TextField(
                              controller: _logoUrlCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Logo (URL or Upload)',
                                prefixIcon: Icon(Icons.image_outlined),
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                final dataUrl = await pickImageDataUrl(maxBytes: 250000);
                                if (dataUrl == null) return;
                                if (!mounted) return;
                                setState(() => _logoUrlCtrl.text = dataUrl);
                              } catch (e) {
                                if (!mounted) return;
                                final msg = e.toString().contains('file_too_large')
                                    ? 'Logo too large (max 250KB).'
                                    : 'Logo upload failed.';
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                              }
                            },
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Upload Logo'),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _logoUrlCtrl.clear()),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                      if (_logoUrlCtrl.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              padding: const EdgeInsets.all(8),
                              child: Image.network(
                                _logoUrlCtrl.text.trim(),
                                height: 56,
                                width: 56,
                                errorBuilder: (context, _, __) => const SizedBox(
                                  height: 56,
                                  width: 56,
                                  child: Center(child: Icon(Icons.broken_image_outlined)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Text('Social Links', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _websiteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Website',
                          prefixIcon: Icon(Icons.public),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _facebookCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Facebook URL',
                          prefixIcon: Icon(Icons.facebook),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _instagramCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Instagram URL',
                          prefixIcon: Icon(Icons.camera_alt_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _whatsappCtrl,
                        decoration: const InputDecoration(
                          labelText: 'WhatsApp',
                          prefixIcon: Icon(Icons.chat_outlined),
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

  Future<void> _openSettingsPdfActions(BuildContext context) async {
    final today = DateTime.now();
    final date = '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Settings PDF'),
          content: const Text('Preview ya download?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runSettingsPdf(context, preview: true, today: date);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runSettingsPdf(context, preview: false, today: date);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runSettingsPdf(BuildContext context, {required bool preview, required String today}) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final bytes = await api.getBytes('/pdf/settings.pdf', token: token);
      final name = 'settings_$today.pdf';
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
        'websiteUrl': _websiteCtrl.text.trim().isEmpty ? null : _websiteCtrl.text.trim(),
        'facebookUrl': _facebookCtrl.text.trim().isEmpty ? null : _facebookCtrl.text.trim(),
        'instagramUrl': _instagramCtrl.text.trim().isEmpty ? null : _instagramCtrl.text.trim(),
        'whatsapp': _whatsappCtrl.text.trim().isEmpty ? null : _whatsappCtrl.text.trim(),
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
