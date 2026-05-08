import 'package:shared_preferences/shared_preferences.dart';

class TokenStore {
  static const _kToken = 'auth_token';
  static const _kTenantSlug = 'tenant_slug';
  static const _kThemeMode = 'theme_mode';

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
}
