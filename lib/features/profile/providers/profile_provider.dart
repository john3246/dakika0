import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/profile_repository.dart';

final profileRepositoryProvider = Provider.autoDispose<ProfileRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ProfileRepository(apiClient);
});

// Profile State Notifier - auto-dispose ensures it rebuilds for each new user.
class ProfileNotifier extends AutoDisposeAsyncNotifier<Map<String, dynamic>> {
  @override
  Future<Map<String, dynamic>> build() => _fetchProfile();

  Future<Map<String, dynamic>> _fetchProfile() async {

    final repo = ref.read(profileRepositoryProvider);
    return repo.getProfile();
  }

  Future<void> fetchProfile() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetchProfile);
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    try {
      final repo = ref.read(profileRepositoryProvider);
      final updatedProfile = await repo.updateProfile(data);
      state = AsyncValue.data(updatedProfile);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> upgradeCourier(Map<String, dynamic> data) async {
    try {
      final repo = ref.read(profileRepositoryProvider);
      final updatedProfile = await repo.upgradeCourier(data);
      state = AsyncValue.data(updatedProfile);
      // Also refresh the cached user in SharedPrefs so isVerified badge updates
      ref.invalidate(currentUserProvider);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> uploadProfileImage(File file) async {
    try {
      final repo = ref.read(profileRepositoryProvider);
      final url = await repo.uploadDocument(file, type: 'profile');

      // ── Update in-memory state ──────────────────────────────────────────────
      final updatedData = Map<String, dynamic>.from(state.value ?? {});
      updatedData['profileImageUrl'] = url;
      state = AsyncValue.data(updatedData);

      // ── Persist to SharedPreferences so the avatar survives app restarts ───
      // We merge the new URL into the cached user_json so currentUserProvider
      // will return the correct image on the very next cold start without a
      // network round-trip.
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('user_json');
        if (raw != null) {
          final userMap = Map<String, dynamic>.from(
            jsonDecode(raw) as Map<String, dynamic>,
          );
          userMap['profileImageUrl'] = url;
          await prefs.setString('user_json', jsonEncode(userMap));
        }
      } catch (_) {
        // SharedPrefs write failure is non-fatal — in-memory state is already updated.
      }
    } catch (e) {
      rethrow;
    }
  }
}

final profileNotifierProvider =
    AsyncNotifierProvider.autoDispose<ProfileNotifier, Map<String, dynamic>>(
  ProfileNotifier.new,
);
