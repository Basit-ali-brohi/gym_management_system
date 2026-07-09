import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'token_store.dart';

/// ── PRODUCTION BACKEND URL ───────────────────────────────────────────────
/// Set this ONCE to your publicly-hosted backend, e.g.
///   const kProductionApiUrl = 'https://gym-api.onrender.com';
/// After that, every RELEASE APK connects automatically — whoever installs it
/// does nothing, no "Server settings", it just works anywhere with internet.
/// Leave empty for local development (uses the localhost fallbacks below).
const kProductionApiUrl = '';

/// Optional compile-time override: flutter build apk --dart-define=API_BASE_URL=...
const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL', defaultValue: '');

String get apiBaseUrl {
  // 1) Explicit build-time override always wins.
  if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
  // 2) Release builds point at the hosted production server, so any APK you
  //    share works with zero setup.
  if (!kDebugMode && kProductionApiUrl.isNotEmpty) return kProductionApiUrl;
  // 3) Local-development fallbacks (debug builds / before deploy).
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

/// The live backend base URL. Defaults to the platform default ([apiBaseUrl])
/// but can be overridden in-app (Login screen → Server settings) and persisted,
/// so a release APK can point at any server IP without a rebuild.
final serverUrlProvider = StateNotifierProvider<ServerUrlController, String>((ref) {
  final store = ref.read(tokenStoreProvider);
  return ServerUrlController(store);
});

class ServerUrlController extends StateNotifier<String> {
  ServerUrlController(this._store) : super(apiBaseUrl) {
    _bootstrap();
  }

  final TokenStore _store;

  /// The compiled-in platform default, used as the "reset" target.
  String get defaultUrl => apiBaseUrl;

  Future<void> _bootstrap() async {
    final saved = normalize(await _store.getServerUrl());
    if (!mounted || saved == null) return;
    state = saved;
  }

  /// Persist + apply a custom server URL. Pass null/empty to reset to default.
  Future<void> setUrl(String? raw) async {
    final normalized = normalize(raw);
    state = normalized ?? apiBaseUrl;
    await _store.setServerUrl(normalized);
  }

  /// Cleans user input: trims, adds http:// if no scheme, strips trailing slash.
  static String? normalize(String? raw) {
    var v = (raw ?? '').trim();
    if (v.isEmpty) return null;
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      v = 'http://$v';
    }
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final base = ref.watch(serverUrlProvider);
  return ApiClient(baseUrl: base);
});

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

/// The brand default — "Gym Floor" ember. Used as the initial value of
/// [accentColorProvider] and as the "reset to default" target.
const kDefaultAccentColor = Color(0xFFFF5A1F);

/// The single unified source of truth for the live brand / primary colour used
/// to build the app theme. Any widget can read it via `ref.watch` and update it
/// via `ref.read(accentColorProvider.notifier).state = newColor`.
final accentColorProvider = StateProvider<Color>((ref) {
  return kDefaultAccentColor; // Default Sunset Orange brand indicator
});

/// Whether the desktop navigation sidebar is pinned open (expanded) rather than
/// the default collapsed hover-to-expand icon rail. Persisted so the choice
/// survives restarts, exactly like [themeModeProvider] / [accentProvider].
final sidebarPinnedProvider = StateNotifierProvider<SidebarPinnedController, bool>((ref) {
  final store = ref.read(tokenStoreProvider);
  return SidebarPinnedController(store);
});

class SidebarPinnedController extends StateNotifier<bool> {
  // Default expanded (labeled) — the "Gym Floor" nav requires a visible icon
  // + label on every item out of the box; hover-to-rail collapse remains
  // available, but is opt-in rather than the default state.
  SidebarPinnedController(this._store) : super(true) {
    _bootstrap();
  }

  final TokenStore _store;

  Future<void> _bootstrap() async {
    final saved = await _store.getSidebarPinned();
    if (mounted && saved != null) state = saved;
  }

  Future<void> setPinned(bool pinned) async {
    state = pinned;
    await _store.setSidebarPinned(pinned);
  }

  Future<void> toggle() => setPinned(!state);
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
