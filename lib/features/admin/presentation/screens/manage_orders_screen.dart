import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/admin_provider.dart';
import '../../data/admin_repository.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/widgets/empty_state_widget.dart';
import '../../../../core/theme/app_colors.dart';

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

        // ── Error state — no raw exception text shown to user ─────────────
        error: (err, stack) => EmptyStateWidget.error(
          onRetry: () => ref.refresh(adminOrdersProvider),
          subtitle: 'Unable to load orders. Tap "Try Again" to reload.',
        ),

        data: (orders) {
          // ── Empty state ──────────────────────────────────────────────────
          if (orders.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.receipt_long_outlined,
              title: 'No Orders Yet',
              subtitle: 'Orders placed by users will appear here.',
              onRetry: () => ref.refresh(adminOrdersProvider),
            );
          }

          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];

              // ── Null-safe ID short display ─────────────────────────────
              final shortId = (order.id.length >= 8)
                  ? '${order.id.substring(0, 8)}…'
                  : order.id;

              // ── Status badge colour ────────────────────────────────────
              final Color statusColor;
              switch (order.status) {
                case 'PENDING':   statusColor = Colors.orange;    break;
                case 'ACCEPTED':  statusColor = Colors.blue;      break;
                case 'PICKED_UP': statusColor = Colors.deepOrange; break;
                case 'DELIVERED': statusColor = Colors.green;     break;
                case 'CANCELLED': statusColor = Colors.red;       break;
                default:          statusColor = Colors.grey;
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: statusColor.withOpacity(0.15),
                    child: Icon(Icons.local_shipping, color: statusColor, size: 20),
                  ),
                  title: Text(
                    'Order #$shortId',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Row(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          order.statusLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'TZS ${order.totalPrice.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Divider(),
                          _infoRow(Icons.person_outline, 'Creator',
                              order.creatorName?.isNotEmpty == true
                                  ? order.creatorName!
                                  : 'User ${order.creatorId.length >= 6 ? order.creatorId.substring(0, 6) : order.creatorId}'),
                          const SizedBox(height: 4),
                          _infoRow(Icons.delivery_dining_outlined, 'Courier',
                              order.courierName ?? 'Unassigned'),
                          const SizedBox(height: 8),
                          _infoRow(Icons.location_on_outlined, 'Pickup',
                              order.pickupAddress.isNotEmpty ? order.pickupAddress : '—'),
                          const SizedBox(height: 4),
                          _infoRow(Icons.flag_outlined, 'Dropoff',
                              order.dropoffAddress.isNotEmpty ? order.dropoffAddress : '—'),
                          const SizedBox(height: 12),

                          // Force-cancel button (only for non-terminal statuses)
                          if (order.status != 'CANCELLED' && order.status != 'DELIVERED')
                            ElevatedButton.icon(
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Cancel Order?'),
                                    content: const Text(
                                        'Are you sure you want to forcibly cancel this order?'),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(c, false),
                                          child: const Text('No')),
                                      TextButton(
                                          onPressed: () => Navigator.pop(c, true),
                                          child: const Text('Yes, Cancel',
                                              style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  try {
                                    await ref
                                        .read(adminRepositoryProvider)
                                        .cancelOrder(order.id);
                                    ref.refresh(adminOrdersProvider);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Row(
                                            children: [
                                              Icon(Icons.check_circle_outline,
                                                  color: Colors.white),
                                              SizedBox(width: 10),
                                              Text('Order cancelled successfully.'),
                                            ],
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          backgroundColor: Colors.grey.shade800,
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12)),
                                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                        ),
                                      );
                                    }
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Text(
                                              'Failed to cancel order. Please try again.'),
                                          backgroundColor: AppColors.error,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12)),
                                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                              icon: const Icon(Icons.cancel_outlined, size: 18),
                              label: const Text('Force Cancel'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade600,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: Colors.grey),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(fontSize: 13, color: Colors.grey)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
