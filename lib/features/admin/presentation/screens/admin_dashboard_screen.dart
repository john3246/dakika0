import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/admin_provider.dart';
import 'manage_users_screen.dart';
import 'manage_orders_screen.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(adminStatsProvider),
          )
        ],
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (stats) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildStatCard(context, 'Total Users', stats['totalUsers'].toString(), Icons.people, Colors.blue),
              _buildStatCard(context, 'Total Couriers', stats['totalCouriers'].toString(), Icons.motorcycle, Colors.orange),
              _buildStatCard(context, 'Pending Verifications', stats['pendingVerifications'].toString(), Icons.verified_user, Colors.red),
              _buildStatCard(context, 'Total Orders', stats['totalOrders'].toString(), Icons.local_shipping, Colors.purple),
              _buildStatCard(context, 'Active Orders', stats['activeOrders'].toString(), Icons.delivery_dining, Colors.green),
              _buildStatCard(context, 'Completed Orders', stats['completedOrders'].toString(), Icons.check_circle, Colors.teal),
              _buildStatCard(context, 'Total Revenue', 'TZS ${stats['totalRevenue']}', Icons.attach_money, Colors.amber),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageUsersScreen()));
                },
                icon: const Icon(Icons.manage_accounts),
                label: const Text('Manage Users & Verifications'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageOrdersScreen()));
                },
                icon: const Icon(Icons.receipt_long),
                label: const Text('Manage Global Orders'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
