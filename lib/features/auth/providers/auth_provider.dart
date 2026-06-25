import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/user_model.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/websocket_service.dart';
import '../data/auth_repository.dart';

// ── Singleton ApiClient ──────────────────────────────────────────────────────
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

// ── AuthRepository ───────────────────────────────────────────────────────────
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});

// ── Current user (read from SharedPreferences after each login/logout) ────────
// This is the single source of truth for the logged-in user object.
final currentUserProvider = FutureProvider<UserModel?>((ref) async {

  final repo = ref.watch(authRepositoryProvider);
  return repo.getStoredUser();
});

// ── Auth state notifier ──────────────────────────────────────────────────────
class AuthNotifier extends StateNotifier<AsyncValue<UserModel?>> {
  final AuthRepository _repository;
  final Ref _ref;

  AuthNotifier(this._repository, this._ref)
      : super(const AsyncValue.data(null));

  /// Login, store the new user's token, then flush ALL cached user-scoped
  /// provider state so every screen rebuilds for the new account.
  Future<void> login(String identifier, String password,
      {bool isEmail = true}) async {
    state = const AsyncValue.loading();
    try {

      final user =
          await _repository.login(identifier, password, isEmail: isEmail);

      // Flush the currentUser cache so it re-reads from SharedPrefs
      _ref.invalidate(currentUserProvider);

      state = AsyncValue.data(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> register(
      String name, String email, String phone, String password) async {
    state = const AsyncValue.loading();
    try {
      await _repository.register(name, email, phone, password);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Logout: clear SharedPreferences token, flush all cached providers.
  Future<void> logout() async {
    try {
      _ref.read(webSocketServiceProvider).disconnect();
    } catch (_) {}
    await _repository.logout();
    _ref.invalidate(currentUserProvider);
    state = const AsyncValue.data(null);
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<UserModel?>>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider), ref);
});
