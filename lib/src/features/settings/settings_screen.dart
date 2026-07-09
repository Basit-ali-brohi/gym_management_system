import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart'; // AppTheme + AppTypography + StatCategory
import '../../core/branding.dart';
import '../../core/gym_floor_components.dart'; // CategoryStatCard
import '../../core/motion.dart';
import '../../core/providers.dart';
import '../../core/in_app_pdf.dart';
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
  final _atRiskDaysCtrl = TextEditingController(text: '3');
  final _atRiskTemplateCtrl = TextEditingController();

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
    _atRiskDaysCtrl.dispose();
    _atRiskTemplateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(settingsProvider);
    final mode = ref.watch(themeModeProvider);
    final isDark = mode == ThemeMode.dark;
    final accentColor = ref.watch(accentColorProvider);
    // "Custom" = the live colour differs from the signature brand default.
    final hasCustomAccent = accentColor != kDefaultAccentColor;

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
          ref.read(animationsEnabledProvider.notifier).state = s.enableAnimations;
          _addressCtrl.text = s.address ?? '';
          _logoUrlCtrl.text = s.logoUrl ?? '';
          _websiteCtrl.text = s.websiteUrl ?? '';
          _facebookCtrl.text = s.facebookUrl ?? '';
          _instagramCtrl.text = s.instagramUrl ?? '';
          _whatsappCtrl.text = s.whatsapp ?? '';
          _atRiskDaysCtrl.text = s.atRiskDays.toString();
          _atRiskTemplateCtrl.text = s.atRiskWhatsAppTemplate ?? '';
        });
      });
    }

    // Compact config field — capped at 450px so text never stretches.
    Widget cfgField(TextEditingController ctrl, String label, IconData icon, {TextInputType? keyboardType}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: TextField(
            controller: ctrl,
            keyboardType: keyboardType,
            style: GoogleFonts.archivo(fontSize: 14),
            decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20)),
          ),
        ),
      );
    }

    // 64x64 rounded logo thumbnail (image preview or minimalist icon).
    Widget logoThumb() {
      final raw = _logoUrlCtrl.text.trim();
      final placeholder = Icon(PhosphorIconsRegular.image, color: theme.colorScheme.onSurfaceVariant, size: 24);
      Widget content = Center(child: placeholder);
      if (raw.isNotEmpty) {
        if (raw.startsWith('data:image')) {
          try {
            final Uint8List bytes = base64Decode(raw.substring(raw.indexOf(',') + 1));
            content = Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (_, _, _) => Center(child: placeholder));
          } catch (_) {
            content = Center(child: placeholder);
          }
        } else {
          content = Image.network(raw, fit: BoxFit.cover, errorBuilder: (_, _, _) => Center(child: placeholder));
        }
      }
      return Container(
        width: 64,
        height: 64,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: AppRadius.smallAll,
          color: isDark ? AppTheme.charcoalHigh : theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: isDark ? AppTheme.borderSubtle : theme.colorScheme.outlineVariant,
            width: 0.8,
          ),
        ),
        child: content,
      );
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: AppPageTitle('Settings')),
                  FilledButton.icon(
                    onPressed: () => _save(context),
                    icon: const Icon(PhosphorIconsRegular.floppyDisk),
                    label: const Text('Save'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'PDF',
                    onPressed: () => _openSettingsPdfActions(context),
                    icon: const Icon(PhosphorIconsRegular.filePdf),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // ── Edge-to-edge 3-up summary grid (matches Staff / app-wide) ──
              LayoutBuilder(
                builder: (context, c) {
                  final tiles = <Widget>[
                    CategoryStatCard(
                      category: StatCategory.operational,
                      label: 'Theme',
                      value: isDark ? 'Dark' : 'Light',
                      footnote: 'ACTIVE MODE',
                    ),
                    CategoryStatCard(
                      category: StatCategory.financial,
                      label: 'Currency',
                      value: _currencyCtrl.text.trim().isEmpty ? 'PKR' : _currencyCtrl.text.trim(),
                      footnote: 'BILLING CURRENCY',
                    ),
                    CategoryStatCard(
                      category: StatCategory.financial,
                      label: 'Tax %',
                      value: _taxCtrl.text.trim().isEmpty ? '0' : _taxCtrl.text.trim(),
                      footnote: 'DEFAULT TAX',
                    ),
                  ];
                  final cols = c.maxWidth >= 720 ? 3 : c.maxWidth >= 460 ? 2 : 1;
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
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
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
                  child: LayoutBuilder(
                    builder: (context, c) {
                      // ── Left column: Gym Profile + logo media ────────────
                      final left = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('GYM PROFILE', style: AppTypography.sectionHeader(color: theme.colorScheme.onSurface)),
                          const SizedBox(height: 14),
                          cfgField(_gymNameCtrl, 'Gym Name', PhosphorIconsRegular.barbell),
                          cfgField(_currencyCtrl, 'Currency', PhosphorIconsRegular.coins),
                          cfgField(_addressCtrl, 'Address', PhosphorIconsRegular.mapPin),
                          const SizedBox(height: 2),
                          Text('Logo',
                              style: GoogleFonts.archivo(
                                  fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              logoThumb(),
                              const SizedBox(width: 14),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      try {
                                        final dataUrl = await pickImageDataUrl(maxBytes: 250000);
                                        if (dataUrl == null) return;
                                        if (!context.mounted) return;
                                        setState(() => _logoUrlCtrl.text = dataUrl);
                                      } catch (e) {
                                        if (!context.mounted) return;
                                        final msg = e.toString().contains('file_too_large')
                                            ? 'Logo too large (max 250KB).'
                                            : 'Logo upload failed.';
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                                      }
                                    },
                                    icon: const Icon(PhosphorIconsRegular.uploadSimple, size: 17),
                                    label: const Text('Upload Logo'),
                                  ),
                                  const SizedBox(height: 4),
                                  if (_logoUrlCtrl.text.trim().isNotEmpty)
                                    TextButton(
                                      onPressed: () => setState(() => _logoUrlCtrl.clear()),
                                      child: const Text('Remove'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      );

                      // ── Right column: Social Links ────────────────────────
                      final right = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SOCIAL LINKS', style: AppTypography.sectionHeader(color: theme.colorScheme.onSurface)),
                          const SizedBox(height: 14),
                          cfgField(_websiteCtrl, 'Website', PhosphorIconsRegular.globeSimple),
                          cfgField(_facebookCtrl, 'Facebook URL', PhosphorIconsRegular.facebookLogo),
                          cfgField(_instagramCtrl, 'Instagram URL', PhosphorIconsRegular.camera),
                          cfgField(_whatsappCtrl, 'WhatsApp', PhosphorIconsRegular.chatCircle),
                        ],
                      );

                      // 50/50 split on wide; stacked on narrow.
                      if (c.maxWidth >= 820) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: left),
                            const SizedBox(width: 28),
                            Expanded(child: right),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [left, const SizedBox(height: 18), right],
                      );
                    },
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
                          prefixIcon: Icon(PhosphorIconsRegular.percent),
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
                      Text('Smart Reminders', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 260,
                            child: TextField(
                              controller: _atRiskDaysCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'At-Risk Days',
                                prefixIcon: Icon(PhosphorIconsRegular.warning),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 720,
                            child: TextField(
                              controller: _atRiskTemplateCtrl,
                              minLines: 2,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: 'WhatsApp Template',
                                helperText: 'Use {name}, {days}, {gym}, {code}',
                                prefixIcon: Icon(PhosphorIconsRegular.fileText),
                              ),
                            ),
                          ),
                        ],
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
                      secondary: const Icon(PhosphorIconsRegular.moon),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            height: 40,
                            width: 40,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: AppRadius.smallAll,
                            ),
                            child: Icon(PhosphorIconsRegular.palette, color: theme.colorScheme.onPrimaryContainer),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Brand Color', style: theme.textTheme.titleMedium),
                                Text(
                                  'Pick any custom accent — applied across the app',
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _BrandColorPickerCard(
                        color: accentColor,
                        isCustom: hasCustomAccent,
                        onTap: () => _openColorPicker(context, ref, accentColor),
                        onReset: hasCustomAccent
                            ? () => ref.read(accentColorProvider.notifier).state = kDefaultAccentColor
                            : null,
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
                      value: _enableSound,
                      onChanged: (v) => setState(() => _enableSound = v),
                      title: const Text('Enable Sounds'),
                      subtitle: const Text('Access denied / success sounds'),
                      secondary: const Icon(PhosphorIconsRegular.speakerHigh),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _enableAnimations,
                      onChanged: (v) {
                        setState(() => _enableAnimations = v);
                        ref.read(animationsEnabledProvider.notifier).state = v;
                      },
                      title: const Text('Enable Animations'),
                      subtitle: const Text('Smooth fade transitions'),
                      secondary: const Icon(PhosphorIconsRegular.sparkle),
                    ),
                  ],
                ),
              ),
              // ── Corporate signature, closing the workspace ───────────────
              const PoweredByDeverosity(
                underline: true,
                padding: EdgeInsets.only(top: 20, bottom: 8),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Opens the full-spectrum colour wheel so the operator can pick ANY brand
  /// colour. On apply, the colour is broadcast app-wide via [accentColorProvider].
  Future<void> _openColorPicker(BuildContext context, WidgetRef ref, Color current) async {
    Color picked = current;
    final theme = Theme.of(context);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          actionsPadding: const EdgeInsets.only(right: 16, bottom: 16, left: 16),
          title: Row(
            children: [
              Icon(PhosphorIconsRegular.palette, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              const Expanded(child: Text('Select Custom Brand Color')),
            ],
          ),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: picked,
              onColorChanged: (color) => picked = color,
              pickerAreaHeightPercent: 0.8,
              enableAlpha: false,
              displayThumbColor: true,
              paletteType: PaletteType.hsvWithHue,
              labelTypes: const [ColorLabelType.hex, ColorLabelType.rgb],
              pickerAreaBorderRadius: const BorderRadius.all(Radius.circular(12)),
              // Dark/obsidian aesthetic for the hex & RGB input fields.
              hexInputBar: true,
              colorPickerWidth: 320,
              portraitOnly: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () {
                ref.read(accentColorProvider.notifier).state = picked;
                Navigator.of(dialogContext).pop();
              },
              child: const Text(
                'APPLY CHANGES',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ),
          ],
        );
      },
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
              icon: const Icon(PhosphorIconsRegular.eye),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runSettingsPdf(context, preview: false, today: date);
              },
              icon: const Icon(PhosphorIconsRegular.downloadSimple),
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
      if (!context.mounted) return;
      await presentPdf(context, preview: preview, bytes: bytes, fileName: name, title: 'Settings Report Preview');
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
      final atRiskDays = int.tryParse(_atRiskDaysCtrl.text.trim());
      final res = await api.putJson('/settings', token: token, body: {
        'gymName': _gymNameCtrl.text.trim().isEmpty ? null : _gymNameCtrl.text.trim(),
        'currency': _currencyCtrl.text.trim().isEmpty ? 'PKR' : _currencyCtrl.text.trim(),
        'defaultTaxPercent': tax,
        'enableSounds': _enableSound,
        'enableAnimations': _enableAnimations,
        'atRiskDays': atRiskDays ?? 3,
        'atRiskWhatsAppTemplate': _atRiskTemplateCtrl.text.trim().isEmpty ? null : _atRiskTemplateCtrl.text.trim(),
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

/// Premium brand-colour preview card. Shows the active colour inside a glowing
/// circular badge plus a "Customize Brand Color" call-to-action that opens the
/// full colour wheel. Replaces the old fixed row of preset swatches.
class _BrandColorPickerCard extends StatelessWidget {
  const _BrandColorPickerCard({
    required this.color,
    required this.isCustom,
    required this.onTap,
    this.onReset,
  });

  final Color color;
  final bool isCustom;
  final VoidCallback onTap;
  final VoidCallback? onReset;

  String get _hex => '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? AppTheme.charcoal
        : theme.colorScheme.surfaceContainerHighest.withAlpha(70);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.large),
            color: bg,
            border: Border.all(color: color.withAlpha(120), width: 1),
          ),
          child: Row(
            children: [
              // Active-colour badge — flat rounded-square, no glow.
              Container(
                height: 52,
                width: 52,
                decoration: BoxDecoration(borderRadius: AppRadius.smallAll, border: Border.all(color: color.withAlpha(70), width: 2)),
                child: Center(
                  child: Container(
                    height: 36,
                    width: 36,
                    decoration: BoxDecoration(borderRadius: AppRadius.smallAll, color: color),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Click to Customize Brand Color',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.archivo(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isCustom)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withAlpha(28),
                              borderRadius: AppRadius.smallAll,
                            ),
                            child: Text(
                              'CUSTOM',
                              style: GoogleFonts.archivo(fontSize: 9.5, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Active: $_hex  •  Full HSV spectrum',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (onReset != null)
                IconButton(
                  tooltip: 'Reset to default',
                  onPressed: onReset,
                  icon: Icon(PhosphorIconsRegular.arrowClockwise, size: 20, color: theme.colorScheme.onSurfaceVariant),
                ),
              Icon(PhosphorIconsRegular.slidersHorizontal, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
