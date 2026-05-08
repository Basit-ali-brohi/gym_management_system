import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../models/models.dart';

class AuthState {
  const AuthState({
    required this.isLoading,
    required this.token,
    required this.user,
    required this.error,
  });

  final bool isLoading;
  final String? token;
  final AuthUser? user;
  final String? error;

  bool get isAuthenticated => token != null && token!.isNotEmpty;

  AuthState copyWith({
    bool? isLoading,
    String? token,
    AuthUser? user,
    String? error,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      token: token ?? this.token,
      user: user ?? this.user,
      error: error,
    );
  }

  static const initial = AuthState(isLoading: true, token: null, user: null, error: null);
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref);
});

class AuthController extends StateNotifier<AuthState> {
  AuthController(this.ref) : super(AuthState.initial) {
    _bootstrap();
  }

  final Ref ref;

  Future<void> _bootstrap() async {
    try {
      final store = ref.read(tokenStoreProvider);
      final token = await store.getToken();
      final tenantSlug = await store.getTenantSlug();
      if (token == null || token.isEmpty) {
        state = state.copyWith(isLoading: false, token: null, user: null, error: null);
        return;
      }

      state = state.copyWith(isLoading: false, token: token, user: null, error: null);
      final api = ref.read(apiClientProvider);
      final me = await api.getJson('/auth/me', token: token);
      state = state.copyWith(user: AuthUser.fromJson({...me, 'tenantSlug': tenantSlug ?? ''}));
    } catch (_) {
      await logout();
    }
  }

  Future<void> login({
    required String tenantSlug,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final api = ref.read(apiClientProvider);
      final store = ref.read(tokenStoreProvider);
      final res = await api.postJson('/auth/login', body: {
        'tenantSlug': tenantSlug.trim(),
        'email': email.trim(),
        'password': password,
      });
      final token = res['token']?.toString() ?? '';
      final userJson = (res['user'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final user = AuthUser.fromJson(userJson);

      await store.setToken(token);
      await store.setTenantSlug(tenantSlug.trim());

      state = AuthState(isLoading: false, token: token, user: user, error: null);
    } on ApiException catch (e) {
      state = AuthState(isLoading: false, token: null, user: null, error: e.message);
    } catch (_) {
      state = AuthState(isLoading: false, token: null, user: null, error: 'login_failed');
    }
  }

  Future<void> logout() async {
    final store = ref.read(tokenStoreProvider);
    await store.clear();
    state = const AuthState(isLoading: false, token: null, user: null, error: null);
  }
}
