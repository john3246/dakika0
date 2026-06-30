import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/admin_provider.dart';
import '../../data/admin_repository.dart';
import '../../../../core/models/order_model.dart';

class ManageOrdersScreen extends ConsumerWidget {
  const ManageOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(adminOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Global Orders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(adminOrdersProvider),
          )
        ],
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (orders) {
          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ExpansionTile(
                  title: Text('Order: ${order.id.substring(0, 8)}...'),
                  subtitle: Text('Status: ${order.status.toUpperCase()} | TZS ${order.totalPrice}'),
                  leading: const Icon(Icons.local_shipping),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Creator: ${order.creatorName ?? order.creatorId}'),
                          Text('Courier: ${order.courierName ?? "Unassigned"}'),
                          const SizedBox(height: 8),
                          Text('Pickup: ${order.pickupAddress}'),
                          Text('Dropoff: ${order.dropoffAddress}'),
                          const Divider(),
                          if (order.status != 'cancelled' && order.status != 'delivered')
                            ElevatedButton.icon(
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Cancel Order?'),
                                    content: const Text('Are you sure you want to forcibly cancel this order?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
                                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes')),
                                    ],
                                  )
                                );
                                if (confirm == true) {
                                  await ref.read(adminRepositoryProvider).cancelOrder(order.id);
                                  ref.refresh(adminOrdersProvider);
                                }
                              },
                              icon: const Icon(Icons.cancel),
                              label: const Text('Force Cancel Order'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            )
                        ],
                      ),
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
