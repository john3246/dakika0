import 'package:dakika0/features/auth/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/demo_mode.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_widgets.dart';
import 'register_screen.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool isEmailLogin = true;
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkServerConnection();
  }

  Future<void> _checkServerConnection() async {
    // ── DEMO MODE: skip server ping ──────────────────────────────────────
    if (kDemoMode) return;
    // ──────────────────────────────────────────────────────────────────────
    final isConnected = await ref.read(apiClientProvider).pingServer();
    if (mounted && isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Connected to Server'),
          backgroundColor: Colors.green.shade600,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Listen to Auth State changes for navigation/errors.
    // State is AsyncValue<UserModel?> â€” data(UserModel) means login succeeded.
    ref.listen(authNotifierProvider, (previous, next) {
      next.when(
        data: (user) {
          // Navigate only when transitioning FROM loading (not on initial null state)
          if (previous != null && previous.isLoading && user != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const DashboardScreen()),
            );
          }
        },
        error: (err, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err.toString())),
          );
        },
        loading: () {},
      );
    });

    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      body: SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height,
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 80),
              // Logo or App Name
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.delivery_dining,
                    size: 64,
                    color: isDark ? AppColors.gold : AppColors.navy,
                  ),
                ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),

              ),
              const SizedBox(height: 40),
              Text(
                context.tr('welcome_back'),
                style: Theme.of(context).textTheme.displayLarge,
              ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.2),
              const SizedBox(height: 8),
              Text(
                context.tr('login_to_continue'),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey,
                    ),
              ).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 40),
              
              // Login Toggle (Email / Phone)
              Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : AppColors.lightGrey,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => isEmailLogin = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isEmailLogin
                                ? (isDark ? AppColors.gold : AppColors.navy)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              context.tr('email'),
                              style: TextStyle(
                                color: isEmailLogin
                                    ? (isDark ? AppColors.navy : Colors.white)
                                    : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => isEmailLogin = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !isEmailLogin
                                ? (isDark ? AppColors.gold : AppColors.navy)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              context.tr('phone'),
                              style: TextStyle(
                                color: !isEmailLogin
                                    ? (isDark ? AppColors.navy : Colors.white)
                                    : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 400.ms),
              
              const SizedBox(height: 24),
              
              if (isEmailLogin)
                CustomTextField(
                  hintText: context.tr('email'),
                  prefixIcon: Icons.email_outlined,
                  controller: _identifierController,
                ).animate().fadeIn(delay: 500.ms)
              else
                CustomTextField(
                  hintText: context.tr('phone'),
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  controller: _identifierController,
                ).animate().fadeIn(delay: 500.ms),
              
              const SizedBox(height: 16),
              CustomTextField(
                hintText: context.tr('password'),
                prefixIcon: Icons.lock_outline,
                isPassword: true,
                controller: _passwordController,
              ).animate().fadeIn(delay: 600.ms),
              
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: Text(context.tr('forgot_password')),
                ),
              ).animate().fadeIn(delay: 700.ms),
              
              const SizedBox(height: 24),
              CustomButton(
                text: context.tr('login'),
                isLoading: authState.isLoading,
                onPressed: () {
                  final id = _identifierController.text.trim();
                  final pass = _passwordController.text;
                  if (id.isEmpty || pass.isEmpty) return;

                  ref.read(authNotifierProvider.notifier).login(
                    id,
                    pass,
                    isEmail: isEmailLogin,
                  );
                },
              ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.1),

              // ── DEMO MODE BANNER ────────────────────────────────────────────
              if (kDemoMode) ...[  
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {
                    ref.read(authNotifierProvider.notifier).login(
                      'demo@dakika0.com',
                      'demo',
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF8C00), Color(0xFFFFB347)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.play_circle_fill, color: Colors.white, size: 22),
                        SizedBox(width: 10),
                        Text(
                          'ENTER DEMO MODE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: 900.ms).slideY(begin: 0.1),
                const SizedBox(height: 4),
                const Center(
                  child: Text(
                    '🟠 Presentation mode — no server needed',
                    style: TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                ),
              ],
              // ── END DEMO BANNER ─────────────────────────────────────────────
              
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(context.tr('dont_have_account')),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RegisterScreen()),
                      );
                    },
                    child: Text(
                      context.tr('register'),
                      style: TextStyle(
                        color: isDark ? AppColors.gold : AppColors.navy,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 1000.ms),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
