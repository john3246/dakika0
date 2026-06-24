import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import 'login_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Wait for the animation to finish, then route based on stored token.
    Future.delayed(const Duration(seconds: 2), _navigate);
  }

  Future<void> _navigate() async {
    if (!mounted) return;
    final repo = ref.read(authRepositoryProvider);
    final isLoggedIn = await repo.isAuthenticated();

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => isLoggedIn ? const DashboardScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delivery_dining,
                size: 100,
                color: AppColors.gold,
              ),
            ).animate().scale(duration: 800.ms, curve: Curves.elasticOut).rotate(delay: 400.ms),
            const SizedBox(height: 24),
            Text(
              "DAKIKA 0",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.gold,
                letterSpacing: 4,
              ),
            ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.5),
            const SizedBox(height: 8),
            const Text(
              "FAST P2P DELIVERY",
              style: TextStyle(
                color: Colors.white54,
                letterSpacing: 2,
              ),
            ).animate().fadeIn(delay: 1200.ms),
          ],
        ),
      ),
    );
  }
}
