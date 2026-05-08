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
