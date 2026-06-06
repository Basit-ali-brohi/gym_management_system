import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'token_store.dart';

const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL', defaultValue: '');

String get apiBaseUrl {
  if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
  if (kIsWeb) {
    final host = Uri.base.host.isEmpty ? '127.0.0.1' : Uri.base.host;
    return 'http://$host:8081';
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8081';
  }
  return 'http://127.0.0.1:8081';
}

/// Identifiers for the global Quick Actions ("+") menu in the app header.
enum QuickAction { addMember, addLead, quickInvoice, recordExpense }

/// Signals a screen to auto-open its create modal once it is the active route.
/// The global "+" menu sets this, navigates to the relevant screen, and the
/// screen consumes (clears) it on first build to launch the matching dialog.
final pendingQuickActionProvider = StateProvider<QuickAction?>((ref) => null);

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(baseUrl: apiBaseUrl));

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  final store = ref.read(tokenStoreProvider);
  return ThemeModeController(store);
});

enum AppAccent {
  gold,
  emerald,
  crimson,
  royalBlue,
  sunsetOrange;

  String get id => switch (this) {
        AppAccent.gold => 'gold',
        AppAccent.emerald => 'emerald',
        AppAccent.crimson => 'crimson',
        AppAccent.royalBlue => 'royal_blue',
        AppAccent.sunsetOrange => 'sunset_orange',
      };

  String get label => switch (this) {
        AppAccent.gold => 'Gold',
        AppAccent.emerald => 'Emerald Green',
        AppAccent.crimson => 'Crimson Red',
        AppAccent.royalBlue => 'Royal Blue',
        AppAccent.sunsetOrange => 'Sunset Orange',
      };

  Color get color => switch (this) {
        AppAccent.gold => const Color(0xFFD4AF37),
        AppAccent.emerald => const Color(0xFF10B981),
        AppAccent.crimson => const Color(0xFFDC2626),
        AppAccent.royalBlue => const Color(0xFF2563EB),
        AppAccent.sunsetOrange => const Color(0xFFF97316),
      };

  static AppAccent fromId(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v == 'emerald') return AppAccent.emerald;
    if (v == 'crimson') return AppAccent.crimson;
    if (v == 'royal_blue') return AppAccent.royalBlue;
    if (v == 'sunset_orange') return AppAccent.sunsetOrange;
    return AppAccent.gold;
  }
}

final accentProvider = StateNotifierProvider<AccentController, AppAccent>((ref) {
  final store = ref.read(tokenStoreProvider);
  return AccentController(store);
});

class AccentController extends StateNotifier<AppAccent> {
  AccentController(this._store) : super(AppAccent.gold) {
    _bootstrap();
  }

  final TokenStore _store;

  Future<void> _bootstrap() async {
    final raw = await _store.getAccent();
    if (!mounted) return;
    state = AppAccent.fromId(raw);
  }

  Future<void> setAccent(AppAccent accent) async {
    state = accent;
    await _store.setAccent(accent.id);
  }
}

/// The brand default — signature Sunset Orange. Used as the initial value of
/// [accentColorProvider] and as the "reset to default" target.
const kDefaultAccentColor = Color(0xFFFF7A00);

/// The single unified source of truth for the live brand / primary colour used
/// to build the app theme. Any widget can read it via `ref.watch` and update it
/// via `ref.read(accentColorProvider.notifier).state = newColor`.
final accentColorProvider = StateProvider<Color>((ref) {
  return kDefaultAccentColor; // Default Sunset Orange brand indicator
});

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._store) : super(ThemeMode.dark) {
    _bootstrap();
  }

  final TokenStore _store;

  Future<void> _bootstrap() async {
    final raw = await _store.getThemeMode();
    final next = raw == 'light' ? ThemeMode.light : ThemeMode.dark;
    if (mounted) state = next;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await _store.setThemeMode(mode == ThemeMode.light ? 'light' : 'dark');
  }
}
