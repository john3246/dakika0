import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Displays a fully scannable QR code for the sender to show to the courier.
///
/// [trackingToken] is the full QR payload string returned by the server:
/// "ORDER:{orderId}|TOKEN:{qrCodeSecureString}"
///
/// The courier's scanner verifies the embedded secure token against the
/// database, completing the proof-of-pickup or proof-of-delivery handshake.
class SenderQrScreen extends StatelessWidget {
  final String trackingToken;

  const SenderQrScreen({super.key, required this.trackingToken});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Show QR to Courier'),
        centerTitle: true,
        automaticallyImplyLeading: false, // prevent accidental back-navigation
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Header ────────────────────────────────────────────────────
                Icon(
                  Icons.qr_code_2_rounded,
                  size: 48,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Show this QR Code to your Courier',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'The courier will scan this to confirm\nproof of pickup.',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 36),

                // ── QR Code Card ──────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white, // always white background for scanner
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: trackingToken,
                    version: QrVersions.auto,
                    size: 240.0,
                    gapless: false,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                    errorStateBuilder: (context, error) => const SizedBox(
                      width: 240,
                      height: 240,
                      child: Center(
                        child: Text(
                          'Could not generate QR code.\nPlease go back and try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Status chip ────────────────────────────────────────────────
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 16, color: Colors.green.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Order broadcasted — awaiting courier',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),

                // ── Done button ────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      // Return all the way to the home screen
                      Navigator.of(context)
                          .popUntil((route) => route.isFirst);
                    },
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Back to Home'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
