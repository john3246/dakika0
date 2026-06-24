import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../orders/providers/order_provider.dart';
import 'delivery_detail_screen.dart';

class ActiveDeliveriesScreen extends ConsumerWidget {
  const ActiveDeliveriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(myActiveOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('active_deliveries')),
        centerTitle: true,
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Failed to load orders', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(myActiveOrdersProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (orders) {
          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_shipping_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No active deliveries',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Orders you place or accept will appear here.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myActiveOrdersProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                return _buildDeliveryCard(context, ref, orders[index]);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeliveryCard(BuildContext context, WidgetRef ref, OrderModel order) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color badgeColor;
    switch (order.status) {
      case 'PENDING':
        badgeColor = Colors.orange;
        break;
      case 'ACCEPTED':
        badgeColor = Colors.blue;
        break;
      case 'PICKED_UP':
        badgeColor = Colors.deepOrange;
        break;
      default:
        badgeColor = Colors.grey;
    }

    Future<void> openDetails() async {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DeliveryDetailScreen(orderId: order.id),
        ),
      );
      ref.invalidate(myActiveOrdersProvider);
      ref.invalidate(orderStatsProvider);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: openDetails,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                backgroundColor: AppColors.gold,
                child: Icon(Icons.delivery_dining, color: AppColors.navy),
              ),
              title: Text(
                order.itemType,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text("From: ${order.pickupAddress}"),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  order.statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Destination",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          order.dropoffAddress,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "TZS ${order.displayPrice.toStringAsFixed(0)}",
                          style: TextStyle(
                            color: isDark ? AppColors.gold : AppColors.navy,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: openDetails,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? AppColors.gold : AppColors.navy,
                      foregroundColor: isDark ? AppColors.navy : Colors.white,
                      minimumSize: const Size(100, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text("Track"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
