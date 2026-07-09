import 'package:shared_preferences/shared_preferences.dart';

class TokenStore {
  static const _kToken = 'auth_token';
  static const _kTenantSlug = 'tenant_slug';
  static const _kThemeMode = 'theme_mode';
  static const _kAccent = 'accent_color';
  static const _kCustomAccent = 'custom_primary_color';
  static const _kServerUrl = 'server_url';
  static const _kSidebarPinned = 'sidebar_pinned';

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kToken);
  }

  Future<void> setToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_kToken);
    } else {
      await prefs.setString(_kToken, token);
    }
  }

  Future<String?> getTenantSlug() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kTenantSlug);
  }

  Future<void> setTenantSlug(String? slug) async {
    final prefs = await SharedPreferences.getInstance();
    if (slug == null || slug.isEmpty) {
      await prefs.remove(_kTenantSlug);
    } else {
      await prefs.setString(_kTenantSlug, slug);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kTenantSlug);
  }

  Future<String?> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kThemeMode);
  }

  Future<void> setThemeMode(String? mode) async {
    final prefs = await SharedPreferences.getInstance();
    if (mode == null || mode.isEmpty) {
      await prefs.remove(_kThemeMode);
    } else {
      await prefs.setString(_kThemeMode, mode);
    }
  }

  Future<String?> getAccent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAccent);
  }

  Future<void> setAccent(String? accent) async {
    final prefs = await SharedPreferences.getInstance();
    if (accent == null || accent.isEmpty) {
      await prefs.remove(_kAccent);
    } else {
      await prefs.setString(_kAccent, accent);
    }
  }

  /// Custom brand colour stored as a 32-bit ARGB int. `null` means the user
  /// has not chosen a custom colour (falls back to the preset accent).
  Future<int?> getCustomAccentColor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kCustomAccent);
  }

  Future<void> setCustomAccentColor(int? argb) async {
    final prefs = await SharedPreferences.getInstance();
    if (argb == null) {
      await prefs.remove(_kCustomAccent);
    } else {
      await prefs.setInt(_kCustomAccent, argb);
    }
  }

  /// Custom backend base URL (e.g. http://192.168.100.11:8081) set in-app, so
  /// the APK can point at the server without a rebuild. Empty/null = default.
  Future<String?> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kServerUrl);
  }

  Future<void> setServerUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      await prefs.remove(_kServerUrl);
    } else {
      await prefs.setString(_kServerUrl, url.trim());
    }
  }

  /// Whether the desktop navigation sidebar is pinned open (expanded) instead of
  /// the default collapsed icon-rail. `null` = not chosen (defaults to rail).
  Future<bool?> getSidebarPinned() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSidebarPinned);
  }

  Future<void> setSidebarPinned(bool? pinned) async {
    final prefs = await SharedPreferences.getInstance();
    if (pinned == null) {
      await prefs.remove(_kSidebarPinned);
    } else {
      await prefs.setBool(_kSidebarPinned, pinned);
    }
  }
}
