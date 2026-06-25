import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      final updatedData = Map<String, dynamic>.from(state.value ?? {});
      updatedData['profileImageUrl'] = url;
      state = AsyncValue.data(updatedData);
    } catch (e) {
      rethrow;
    }
  }
}

final profileNotifierProvider =
    AsyncNotifierProvider.autoDispose<ProfileNotifier, Map<String, dynamic>>(
  ProfileNotifier.new,
);
