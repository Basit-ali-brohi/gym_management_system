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

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(baseUrl: apiBaseUrl));

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  final store = ref.read(tokenStoreProvider);
  return ThemeModeController(store);
});

enum AppAccent {
  gold,
  emerald,
  crimson;

  String get id => switch (this) {
        AppAccent.gold => 'gold',
        AppAccent.emerald => 'emerald',
        AppAccent.crimson => 'crimson',
      };

  String get label => switch (this) {
        AppAccent.gold => 'Gold',
        AppAccent.emerald => 'Emerald Green',
        AppAccent.crimson => 'Crimson Red',
      };

  Color get color => switch (this) {
        AppAccent.gold => const Color(0xFFD4AF37),
        AppAccent.emerald => const Color(0xFF10B981),
        AppAccent.crimson => const Color(0xFFDC2626),
      };

  static AppAccent fromId(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v == 'emerald') return AppAccent.emerald;
    if (v == 'crimson') return AppAccent.crimson;
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
