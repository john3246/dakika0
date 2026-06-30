import 'package:flutter/material.dart';

class CourierScannerScreen extends StatelessWidget {
  final String title;
  final Function(String) onScan;

  const CourierScannerScreen({
    super.key,
    required this.title,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Scanner Placeholder', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => onScan('dummy-qr-code'),
              child: const Text('Simulate Scan'),
            ),
          ],
        ),
      ),
    );
  }
}
