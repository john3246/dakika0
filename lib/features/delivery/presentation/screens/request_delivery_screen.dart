// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_widgets.dart';
import '../../../../core/services/location_service.dart';
import 'order_verification_screen.dart';

class RequestDeliveryScreen extends ConsumerStatefulWidget {
  const RequestDeliveryScreen({super.key});

  @override
  ConsumerState<RequestDeliveryScreen> createState() =>
      _RequestDeliveryScreenState();
}

class _RequestDeliveryScreenState
    extends ConsumerState<RequestDeliveryScreen> {
  final _pickupController       = TextEditingController();
  final _dropoffController      = TextEditingController();
  final _itemTypeController     = TextEditingController();
  final _weightController       = TextEditingController();
  final _suggestedPriceController = TextEditingController();

  bool _isLoadingLocation = false;
  double? _pickupLat;
  double? _pickupLng;

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _itemTypeController.dispose();
    _weightController.dispose();
    _suggestedPriceController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchLocation();
  }

  Future<void> _fetchLocation() async {
    setState(() => _isLoadingLocation = true);
    final locationService = LocationService();
    final hasPermission = await locationService.requestPermission();
    if (hasPermission) {
      final position = await locationService.getCurrentLocation();
      if (position != null) {
        setState(() {
          _pickupLat = position.latitude;
          _pickupLng = position.longitude;
          // Show coordinates immediately while geocoding resolves
          _pickupController.text = 'Locating address…';
        });

        // Reverse-geocode in background — update the field when resolved
        final address = await locationService.getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (mounted) {
          setState(() {
            _pickupController.text = address;
          });
        }
      }
    }
    if (mounted) {
      setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _proceedToVerification() async {
    final pickup  = _pickupController.text.trim();
    final dropoff = _dropoffController.text.trim();
    final item    = _itemTypeController.text.trim();

    if (pickup.isEmpty || dropoff.isEmpty || item.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in pickup, destination and item type.')),
      );
      return;
    }

    if (_pickupLat == null || _pickupLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for GPS location or ensure permissions are granted.')),
      );
      return;
    }

    // TODO: Forward-geocode the typed dropoff address to get real coordinates.
    // For now we use the pickup coords as a safe fallback so the API call
    // never sends random garbage; the user sees a ~0 km distance estimate
    // which is clearly wrong and prompts them to add a real address.
    final dropoffLat = _pickupLat!;
    final dropoffLng = _pickupLng!;

    final weight = double.tryParse(_weightController.text.trim());
    final suggestedPrice = double.tryParse(_suggestedPriceController.text.trim());

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderVerificationScreen(
          pickupAddress: pickup,
          dropoffAddress: dropoff,
          itemType: item,
          packageWeightKg: weight,
          suggestedPrice: suggestedPrice,
          pickupLat: _pickupLat!,
          pickupLng: _pickupLng!,
          dropoffLat: dropoffLat,
          dropoffLng: dropoffLng,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('request_delivery')),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Pickup ─────────────────────────────────────────────────
            Row(
              children: [
                const Text(
                  "Where is the pickup?",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isLoadingLocation) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 12),
            CustomTextField(
              hintText: context.tr('pickup_location'),
              prefixIcon: Icons.location_on_outlined,
              controller: _pickupController,
              readOnly: false, // Allow manual entry if GPS fails
            ),

            const SizedBox(height: 24),

            // ── Dropoff ────────────────────────────────────────────────
            const Text(
              "Where is the destination?",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            CustomTextField(
              hintText: context.tr('destination'),
              prefixIcon: Icons.flag_outlined,
              controller: _dropoffController,
            ),

            const SizedBox(height: 24),

            // ── Package details ────────────────────────────────────────
            const Text(
              "Package details",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            CustomTextField(
              hintText: "Item type (e.g. Documents, Phone, Clothing)",
              prefixIcon: Icons.inventory_2_outlined,
              controller: _itemTypeController,
            ),
            const SizedBox(height: 12),
            CustomTextField(
              hintText: "Weight in kg (optional)",
              prefixIcon: Icons.scale_outlined,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              controller: _weightController,
            ),

            const SizedBox(height: 32),

            // ── Dynamic Pricing Info ───────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : AppColors.lightGrey,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.calculate_outlined, color: AppColors.navy, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Price is auto-calculated based on distance",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white70 : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Text("Formula: ", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text(
                        "TZS 2,000 base + TZS 500/km",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? AppColors.gold : AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Suggested Price Override ────────────────────────────────
            const Text(
              "Your offer (optional)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Set your own price to attract couriers faster",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 12),
            CustomTextField(
              hintText: "Suggested price (e.g. 5000)",
              prefixIcon: Icons.money,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              controller: _suggestedPriceController,
            ),

            const SizedBox(height: 40),

            // ── Proceed to Verification ──────────────────────────────
            CustomButton(
              text: 'Verify & Confirm',
              onPressed: _proceedToVerification,
            ),
          ],
        ),
      ),
    );
  }
}
