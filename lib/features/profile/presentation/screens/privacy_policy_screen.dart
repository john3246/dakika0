import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security & Privacy'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.security, size: 64, color: Colors.blueGrey),
            const SizedBox(height: 24),
            const Text(
              'Privacy Policy',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Welcome to Dakika0. We are committed to protecting your privacy and ensuring the security of your personal and delivery data.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 24),
            _buildSection(
              title: '1. Information We Collect',
              content: 'We collect personal information such as your name, email, phone number, and location data to facilitate real-time peer-to-peer delivery services. If you register as a courier, we also collect your National ID (NIDA) and vehicle registration details.',
            ),
            _buildSection(
              title: '2. How We Use Your Information',
              content: 'Your location data is used to match senders with nearby couriers and track active deliveries. Your contact information is used to enable secure in-app communication (via the native dialer) between senders and couriers.',
            ),
            _buildSection(
              title: '3. Data Security',
              content: 'All API communications are secured over standard protocols. Your passwords are hashed using bcrypt, and sensitive authentication tokens are stored securely on your device.',
            ),
            _buildSection(
              title: '4. Third-Party Sharing',
              content: 'We do not sell your personal data to third parties. Data is only shared with the assigned courier or sender to facilitate the delivery transaction.',
            ),
            const SizedBox(height: 40),
            Center(
              child: Text(
                'Last Updated: June 2026',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required String content}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.5),
          ),
        ],
      ),
    );
  }
}
