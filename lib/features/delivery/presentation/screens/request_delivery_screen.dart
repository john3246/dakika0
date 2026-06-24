// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_widgets.dart';
import '../../../orders/providers/order_provider.dart';

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

  bool _isSubmitting = false;

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _itemTypeController.dispose();
    _weightController.dispose();
    _suggestedPriceController.dispose();
    super.dispose();
  }

  Future<void> _submitOrder() async {
    final pickup  = _pickupController.text.trim();
    final dropoff = _dropoffController.text.trim();
    final item    = _itemTypeController.text.trim();

    if (pickup.isEmpty || dropoff.isEmpty || item.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in pickup, destination and item type.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final repo   = ref.read(orderRepositoryProvider);
      final weight = double.tryParse(_weightController.text.trim());
      final suggestedPrice = double.tryParse(_suggestedPriceController.text.trim());

      await repo.createOrder(
        pickupAddress:  pickup,
        dropoffAddress: dropoff,
        itemType:       item,
        packageWeightKg: weight,
        suggestedPrice: suggestedPrice,
      );

      // Refresh the active orders list and stats
      ref.invalidate(myActiveOrdersProvider);
      ref.invalidate(orderStatsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order placed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
            const Text(
              "Where is the pickup?",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            CustomTextField(
              hintText: context.tr('pickup_location'),
              prefixIcon: Icons.location_on_outlined,
              controller: _pickupController,
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

            // ── Submit ─────────────────────────────────────────────────
            CustomButton(
              text: context.tr('confirm_order'),
              isLoading: _isSubmitting,
              onPressed: _submitOrder,
            ),
          ],
        ),
      ),
    );
  }
}
