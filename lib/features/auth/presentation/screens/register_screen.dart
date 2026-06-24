import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_widgets.dart';
import 'otp_screen.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen(authNotifierProvider, (previous, next) {
      next.when(
        data: (_) {
          if (next.isLoading) return;
          if (previous != null && previous.isLoading) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Registration successful! Please login.')),
             );
             Navigator.pop(context); // Go back to login
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: isDark ? Colors.white : AppColors.navy),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('register'),
              style: Theme.of(context).textTheme.displayLarge,
            ).animate().fadeIn().slideX(begin: -0.2),
            const SizedBox(height: 8),
            Text(
              "Create an account to start delivering",
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey,
                  ),
            ).animate().fadeIn(delay: 100.ms),
            const SizedBox(height: 40),
            CustomTextField(
              hintText: context.tr('full_name'),
              prefixIcon: Icons.person_outline,
              controller: _nameController,
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 16),
            CustomTextField(
              hintText: context.tr('email'),
              prefixIcon: Icons.email_outlined,
              controller: _emailController,
            ).animate().fadeIn(delay: 300.ms),
            const SizedBox(height: 16),
            CustomTextField(
              hintText: context.tr('phone'),
              prefixIcon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              controller: _phoneController,
            ).animate().fadeIn(delay: 400.ms),
            const SizedBox(height: 16),
            CustomTextField(
              hintText: context.tr('password'),
              prefixIcon: Icons.lock_outline,
              isPassword: true,
              controller: _passwordController,
            ).animate().fadeIn(delay: 500.ms),
            const SizedBox(height: 16),
            CustomTextField(
              hintText: context.tr('confirm_password'),
              prefixIcon: Icons.lock_outline,
              isPassword: true,
              controller: _confirmPasswordController,
            ).animate().fadeIn(delay: 600.ms),
            const SizedBox(height: 32),
            CustomButton(
              text: context.tr('create_account'),
              isLoading: authState.isLoading,
              onPressed: () {
                final name = _nameController.text.trim();
                final email = _emailController.text.trim();
                final phone = _phoneController.text.trim();
                final pass = _passwordController.text;
                final confirmPass = _confirmPasswordController.text;

                if (name.isEmpty || email.isEmpty || phone.isEmpty || pass.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields')),
                  );
                  return;
                }
                if (pass != confirmPass) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Passwords do not match')),
                  );
                  return;
                }

                ref.read(authNotifierProvider.notifier).register(
                  name,
                  email,
                  phone,
                  pass,
                );
              },
            ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.1),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(context.tr('already_have_account')),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    context.tr('login'),
                    style: TextStyle(
                      color: isDark ? AppColors.gold : AppColors.navy,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ).animate().fadeIn(delay: 800.ms),
          ],
        ),
      ),
    );
  }
}
