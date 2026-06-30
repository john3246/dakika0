import 'package:flutter/material.dart';

class SenderQrScreen extends StatelessWidget {
  final String trackingToken;
  const SenderQrScreen({super.key, required this.trackingToken});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Show QR to Courier')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('QR Code Placeholder', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 20),
            Text(trackingToken),
          ],
        ),
      ),
    );
  }
}
