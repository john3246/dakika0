import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../delivery/presentation/screens/request_delivery_screen.dart';
import '../../../delivery/presentation/screens/delivery_detail_screen.dart';
import '../../../orders/providers/order_provider.dart';
import '../../../profile/providers/profile_provider.dart';
import 'courier_map_feed_screen.dart';
import '../../../orders/presentation/screens/order_history_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _pickAndUploadImage(WidgetRef ref) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      ref.read(profileNotifierProvider.notifier).uploadProfileImage(File(pickedFile.path));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserAsync = ref.watch(currentUserProvider);
    final user             = currentUserAsync.valueOrNull;
    final userName         = user?.name  ?? 'User';
    final isVerified       = user?.isFullyVerified ?? false;
    final userPhone        = user?.phone ?? '';

    final profileState    = ref.watch(profileNotifierProvider);
    final profileImageUrl = profileState.valueOrNull?['profileImageUrl'] as String? ?? user?.profileImageUrl;

    final activeOrdersAsync = ref.watch(myActiveOrdersProvider);
    final statsAsync        = ref.watch(orderStatsProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            GestureDetector(
              onTap: () => _pickAndUploadImage(ref),
              child: CircleAvatar(
                backgroundColor: AppColors.gold,
                backgroundImage: profileImageUrl != null ? NetworkImage(profileImageUrl) : null,
                child: profileImageUrl == null ? const Icon(Icons.person, color: AppColors.navy) : null,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Hello, $userName",
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  "${isVerified ? '✓ Verified' : 'Sender'} • $userPhone",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myActiveOrdersProvider);
          ref.invalidate(orderStatsProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  image: const DecorationImage(
                    image: AssetImage('assets/images/background.jpg'),
                    fit: BoxFit.cover,
                    opacity: 0.5,
                  ),
                  gradient: LinearGradient(
                    colors: [AppColors.navy, AppColors.navy.withOpacity(0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0, left: 3.0, right: 2.0),
                        child: Text(
                          "Tuma , Popote",
                          style: TextStyle(color: AppColors.gold, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          "Fast and reliable peer-to-peer delivery service at your fingertips.",
                          style: TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const RequestDeliveryScreen()),
                          );
                          ref.invalidate(myActiveOrdersProvider);
                          ref.invalidate(orderStatsProvider);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: AppColors.navy,
                        ),
                        child: Text(context.tr('request_delivery')),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn().scale(delay: 200.ms),
              const SizedBox(height: 20),
              if (isVerified)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CourierMapFeedScreen()),
                      );
                      ref.invalidate(myActiveOrdersProvider);
                      ref.invalidate(orderStatsProvider);
                    },
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Find Nearby Orders'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),
              const SizedBox(height: 10),
              Text('My Requests & Active', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              activeOrdersAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, _) => Center(child: Text('Error loading orders: $e')),
                data: (orders) {
                  if (orders.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: const Center(
                        child: Column(
                          children: [
                            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('No active deliveries', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.local_shipping, color: AppColors.navy),
                          ),
                          title: Text(order.itemType),
                          subtitle: Text(order.pickupAddress),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.navy.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              order.statusLabel,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => DeliveryDetailScreen(orderId: order.id)),
                            );
                            ref.invalidate(myActiveOrdersProvider);
                            ref.invalidate(orderStatsProvider);
                          },
                        ),
                      ).animate().fadeIn(delay: (200 + (index * 80)).ms).slideX(begin: 0.1);
                    },
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(context.tr('recent_orders'), style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              statsAsync.when(
                loading: () => const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => Row(
                  children: [
                    _buildStatCard(context, ref, "Completed", "—", Icons.check_circle_outline),
                    const SizedBox(width: 16),
                    _buildStatCard(context, ref, "Canceled", "—", Icons.cancel_outlined),
                  ],
                ),
                data: (stats) => Row(
                  children: [
                    _buildStatCard(context, ref, "Completed", '${stats['DELIVERED'] ?? 0}', Icons.check_circle_outline),
                    const SizedBox(width: 16),
                    _buildStatCard(context, ref, "Canceled", '${stats['CANCELLED'] ?? 0}', Icons.cancel_outlined),
                  ],
                ).animate().fadeIn(delay: 700.ms),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, WidgetRef ref, String title, String value, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
          );
          ref.invalidate(orderStatsProvider);
          ref.invalidate(myActiveOrdersProvider);
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : AppColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.navy),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text(title, style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
