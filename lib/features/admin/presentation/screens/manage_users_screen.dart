import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/admin_provider.dart';
import '../../data/admin_repository.dart';
import '../../../../core/models/user_model.dart';

class ManageUsersScreen extends ConsumerStatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  ConsumerState<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends ConsumerState<ManageUsersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All Users'),
            Tab(text: 'Couriers (Verifications)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUsersList(),
          _buildCouriersList(),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    final usersAsync = ref.watch(adminUsersProvider);
    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
      data: (users) {
        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return _UserTile(user: user, isCourierTab: false);
          },
        );
      },
    );
  }

  Widget _buildCouriersList() {
    final couriersAsync = ref.watch(adminCouriersProvider);
    return couriersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
      data: (couriers) {
        return ListView.builder(
          itemCount: couriers.length,
          itemBuilder: (context, index) {
            final courier = couriers[index];
            return _UserTile(user: courier, isCourierTab: true);
          },
        );
      },
    );
  }
}

class _UserTile extends ConsumerWidget {
  final UserModel user;
  final bool isCourierTab;

  const _UserTile({required this.user, required this.isCourierTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        title: Text(user.name),
        subtitle: Text('${user.email} | Role: ${user.role}'),
        leading: Icon(
          user.isActive ? Icons.person : Icons.person_off,
          color: user.isActive ? Colors.green : Colors.red,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Phone: ${user.phone}'),
                Text('Created: ${user.createdAt?.toLocal()}'),
                if (isCourierTab) ...[
                  const Divider(),
                  Text('Vehicle: ${user.vehicleType ?? "N/A"}'),
                  Text('Reg Number: ${user.vehicleRegistrationNumber ?? "N/A"}'),
                  Text('NIDA: ${user.nidaNumber ?? "N/A"}'),
                  Text('Verified: ${user.isVerified == true ? "YES" : "NO"}', 
                    style: TextStyle(color: user.isVerified == true ? Colors.green : Colors.red, fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: user.isVerified == true ? null : () async {
                          await ref.read(adminRepositoryProvider).verifyCourier(user.id, true);
                          ref.refresh(adminCouriersProvider);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        child: const Text('Approve Courier'),
                      ),
                      ElevatedButton(
                        onPressed: user.isVerified == false ? null : () async {
                          await ref.read(adminRepositoryProvider).verifyCourier(user.id, false);
                          ref.refresh(adminCouriersProvider);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text('Revoke'),
                      ),
                    ],
                  ),
                ],
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Active Status:'),
                    Switch(
                      value: user.isActive,
                      onChanged: (val) async {
                        await ref.read(adminRepositoryProvider).toggleUserActive(user.id, val);
                        ref.refresh(adminUsersProvider);
                        ref.refresh(adminCouriersProvider);
                      },
                    ),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
