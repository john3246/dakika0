import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/models/user_model.dart';
import '../../../../core/models/order_model.dart';
import '../data/admin_repository.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AdminRepository(apiClient);
});

final adminStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(adminRepositoryProvider).getStats();
});

final adminUsersProvider = FutureProvider.autoDispose<List<UserModel>>((ref) async {
  return ref.watch(adminRepositoryProvider).getUsers();
});

final adminCouriersProvider = FutureProvider.autoDispose<List<UserModel>>((ref) async {
  return ref.watch(adminRepositoryProvider).getCouriers();
});

final adminOrdersProvider = FutureProvider.autoDispose<List<OrderModel>>((ref) async {
  return ref.watch(adminRepositoryProvider).getOrders();
});
