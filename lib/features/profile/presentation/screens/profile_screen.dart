import 'dart:io';
import 'package:dakika0/features/profile/providers/profile_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../orders/presentation/screens/order_history_screen.dart';
import 'privacy_policy_screen.dart';
import 'verification_wizard_screen.dart';
import '../../../admin/presentation/screens/admin_dashboard_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider);
    final profileState = ref.watch(profileNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('profile')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: profileState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (profileData) {
          final imageUrl = profileData['profileImageUrl'];
          final courierStatus = profileData['courierStatus'] as String? ?? 'unverified';
          final isVerified = profileData['isFullyVerified'] as bool? ?? false;
          final senderRating = profileData['senderRating'];
          final courierRating = profileData['courierRating'];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // â”€â”€ Profile Image â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                    if (pickedFile != null) {
                      ref.read(profileNotifierProvider.notifier).uploadProfileImage(File(pickedFile.path));
                    }
                  },
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: AppColors.gold,
                        backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
                        child: imageUrl == null ? const Icon(Icons.person, size: 60, color: AppColors.navy) : null,
                      ),
                      if (isVerified)
                        Positioned(
                          bottom: 0,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, size: 18, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  profileData['name'] ?? 'Unknown User',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Text(
                  profileData['email'] ?? '',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),

                // â”€â”€ Ratings Row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildRatingChip('Sender', senderRating, Icons.send),
                    const SizedBox(width: 12),
                    _buildRatingChip('Courier', courierRating, Icons.delivery_dining),
                  ],
                ),

                const SizedBox(height: 24),

                // â”€â”€ Verification Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                if (!isVerified)
                  _buildVerificationCard(context, ref, courierStatus, isDark),
                
                if (isVerified)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.verified, color: Colors.green, size: 28),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Verified Courier', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                              Text('You can send and deliver packages', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),
            
                _buildProfileSection(
                  context,
                  title: "General Settings",
                  items: [
                    _buildProfileItem(
                      context,
                      icon: Icons.language,
                      title: context.tr('language'),
                      trailing: DropdownButton<String>(
                        value: locale.languageCode,
                        underline: const SizedBox(),
                        onChanged: (value) {
                          if (value != null) {
                            ref.read(localeProvider.notifier).state = Locale(value);
                          }
                        },
                        items: [
                          DropdownMenuItem(value: 'en', child: Text(context.tr('english'))),
                          DropdownMenuItem(value: 'sw', child: Text(context.tr('swahili'))),
                        ],
                      ),
                    ),
                    _buildProfileItem(
                      context,
                      icon: isDark ? Icons.dark_mode : Icons.light_mode,
                      title: context.tr('dark_mode'),
                      trailing: Switch(
                        value: isDark,
                        onChanged: (value) {
                          ref.read(themeProvider.notifier).toggleTheme();
                        },
                        activeColor: AppColors.gold,
                      ),
                    ),
                  ],
                ),
            
                const SizedBox(height: 24),
            
                _buildProfileSection(
                  context,
                  title: context.tr('user_management'),
                  items: [
                    _buildProfileItem(context, icon: Icons.security, title: "Security & Privacy", onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
                    }),
                    _buildProfileItem(context, icon: Icons.payment, title: "Payment Methods", onTap: () {}),
                    _buildProfileItem(context, icon: Icons.history, title: "Order History", onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderHistoryScreen()));
                    }),
                  ],
                ),
            
                if (profileData['role'] == 'ADMIN') ...[
                  const SizedBox(height: 24),
                  _buildProfileSection(
                    context,
                    title: 'System Administration',
                    items: [
                      _buildProfileItem(
                        context,
                        icon: Icons.admin_panel_settings,
                        title: 'Super Admin Dashboard',
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen()));
                        },
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 32),
            
                ListTile(
                  onTap: () async {
                    await ref.read(authNotifierProvider.notifier).logout();
                    if (context.mounted) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const LoginScreen()),
                        (route) => false,
                      );
                    }
                  },
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: Text(
                    context.tr('logout'),
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Colors.red.withValues(alpha: 0.05),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRatingChip(String label, dynamic rating, IconData icon) {
    final value = (rating is num) ? rating.toStringAsFixed(1) : '5.0';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.navy),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const Icon(Icons.star, size: 14, color: AppColors.gold),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildVerificationCard(BuildContext context, WidgetRef ref, String status, bool isDark) {
    final isPending = status == 'pending';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPending
              ? [Colors.orange.withValues(alpha: 0.15), Colors.orange.withValues(alpha: 0.05)]
              : [AppColors.navy.withValues(alpha: 0.12), AppColors.navy.withValues(alpha: 0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPending ? Colors.orange.withValues(alpha: 0.3) : AppColors.navy.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPending ? Icons.hourglass_top : Icons.delivery_dining,
                color: isPending ? Colors.orange : AppColors.navy,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPending ? 'Verification Pending' : 'Want to Earn Money?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isPending ? Colors.orange.shade800 : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPending
                          ? 'Your documents are being reviewed. We will notify you once approved.'
                          : 'Become a verified courier and start delivering packages in your area.',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isPending) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const VerificationWizardScreen()),
                  ).then((_) {
                    // Refresh profile after wizard closes
                    ref.read(profileNotifierProvider.notifier).fetchProfile();
                  });
                },
                icon: const Icon(Icons.upload_file),
                label: const Text('Verify Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileSection(BuildContext context, {required String title, required List<Widget> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
          ),
        ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
          ),
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _buildProfileItem(BuildContext context,
      {required IconData icon, required String title, Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppColors.navy),
      title: Text(title),
      trailing: trailing ?? const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
    );
  }
}
