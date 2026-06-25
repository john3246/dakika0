import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/services/websocket_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/order_repository.dart';

final orderRepositoryProvider = Provider.autoDispose<OrderRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return OrderRepository(apiClient);
});

final myActiveOrdersProvider =
    AsyncNotifierProvider.autoDispose<MyActiveOrdersNotifier, List<OrderModel>>(
  MyActiveOrdersNotifier.new,
);

class MyActiveOrdersNotifier extends AutoDisposeAsyncNotifier<List<OrderModel>> {
  @override
  Future<List<OrderModel>> build() {
    final ws = ref.watch(webSocketServiceProvider);
    final sub = ws.eventStream.listen((event) {
      if (['order_created', 'order_accepted', 'order_picked_up', 'order_delivered', 'order_cancelled', 'delivery_location_update']
          .contains(event['eventType'] ?? event['type'])) {
        ref.invalidateSelf();
      }
    });
    ref.onDispose(() => sub.cancel());
    
    return _fetch();
  }

  Future<List<OrderModel>> _fetch() {
    return ref.read(orderRepositoryProvider).getMyOrders(statusFilter: 'PENDING,ACCEPTED,PICKED_UP');
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}

final myOrderHistoryProvider =
    FutureProvider.autoDispose<List<OrderModel>>((ref) async {
  return ref.watch(orderRepositoryProvider).getMyOrders(statusFilter: 'DELIVERED,CANCELLED');
});

final availableOrdersProvider =
    AsyncNotifierProvider.autoDispose<AvailableOrdersNotifier, List<OrderModel>>(
  AvailableOrdersNotifier.new,
);

class AvailableOrdersNotifier extends AutoDisposeAsyncNotifier<List<OrderModel>> {
  @override
  Future<List<OrderModel>> build() {
    final ws = ref.watch(webSocketServiceProvider);
    final sub = ws.eventStream.listen((event) {
      if (['order_created', 'order_accepted', 'order_broadcast']
          .contains(event['eventType'] ?? event['type'])) {
        ref.invalidateSelf();
      }
    });
    ref.onDispose(() => sub.cancel());
    
    return _fetch();
  }

  Future<List<OrderModel>> _fetch() {
    return ref.read(orderRepositoryProvider).getAvailableOrders();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}

final orderDetailProvider =
    FutureProvider.autoDispose.family<OrderModel, String>((ref, orderId) {
  final timer = Timer.periodic(const Duration(seconds: 5), (_) => ref.invalidateSelf());
  ref.onDispose(() => timer.cancel());
  return ref.watch(orderRepositoryProvider).getOrderById(orderId);
});

final orderStatsProvider =
    AsyncNotifierProvider.autoDispose<OrderStatsNotifier, Map<String, int>>(
  OrderStatsNotifier.new,
);

class OrderStatsNotifier extends AutoDisposeAsyncNotifier<Map<String, int>> {
  @override
  Future<Map<String, int>> build() {
    final ws = ref.watch(webSocketServiceProvider);
    final sub = ws.eventStream.listen((event) {
      if (['order_created', 'order_delivered', 'order_cancelled']
          .contains(event['eventType'] ?? event['type'])) {
        ref.invalidateSelf();
      }
    });
    ref.onDispose(() => sub.cancel());
    return _fetch();
  }

  Future<Map<String, int>> _fetch() {
    return ref.read(orderRepositoryProvider).getMyStats();
  }
}
