import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math' as math;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_widgets.dart';
import '../../../orders/providers/order_provider.dart';
import 'sender_qr_screen.dart';

class OrderVerificationScreen extends ConsumerStatefulWidget {
  final String pickupAddress;
  final String dropoffAddress;
  final String itemType;
  final double? packageWeightKg;
  final double? suggestedPrice;
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;

  const OrderVerificationScreen({
    super.key,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.itemType,
    this.packageWeightKg,
    this.suggestedPrice,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
  });

  @override
  ConsumerState<OrderVerificationScreen> createState() => _OrderVerificationScreenState();
}

class _OrderVerificationScreenState extends ConsumerState<OrderVerificationScreen> {
  bool _isSubmitting = false;
  late double _distanceKm;
  late double _totalPrice;

  @override
  void initState() {
    super.initState();
    _calculateDistanceAndPrice();
  }

  void _calculateDistanceAndPrice() {
    // Ensure coordinates are numeric
    final double pickupLat = double.tryParse(widget.pickupLat.toString()) ?? 0.0;
    final double pickupLng = double.tryParse(widget.pickupLng.toString()) ?? 0.0;
    final double dropoffLat = double.tryParse(widget.dropoffLat.toString()) ?? 0.0;
    final double dropoffLng = double.tryParse(widget.dropoffLng.toString()) ?? 0.0;

    const double R = 6371;
    final dLat = _deg2rad(dropoffLat - pickupLat);
    final dLon = _deg2rad(dropoffLng - pickupLng);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(pickupLat)) * math.cos(_deg2rad(dropoffLat)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    _distanceKm = R * c;
    _totalPrice = _distanceKm * 500;
  }

  double _deg2rad(double deg) {
    return deg * (math.pi / 180);
  }

  Future<void> _submitOrder() async {
    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(orderRepositoryProvider);
      final order = await repo.createOrder(
        pickupAddress: widget.pickupAddress,
        dropoffAddress: widget.dropoffAddress,
        itemType: widget.itemType,
        packageWeightKg: widget.packageWeightKg,
        suggestedPrice: widget.suggestedPrice,
        pickupLatitude: widget.pickupLat,
        pickupLongitude: widget.pickupLng,
        dropoffLatitude: widget.dropoffLat,
        dropoffLongitude: widget.dropoffLng,
      );

      ref.invalidate(myActiveOrdersProvider);
      ref.invalidate(orderStatsProvider);
      ref.invalidate(availableOrdersProvider);

      if (mounted) {
        // ── ✅ Navigate to the QR screen so the sender can show the courier ─
        final qrToken = order.qrPayload ?? order.qrCodeSecureString ?? order.id;

        // Pop the verification screen first, then push QR screen in its place
        Navigator.pop(context); // back to request_delivery_screen
        Navigator.pushReplacement(
          // ignore: use_build_context_synchronously
          context,
          MaterialPageRoute(
            builder: (_) => SenderQrScreen(trackingToken: qrToken),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // ── ⚠️ Failure Snackbar ──────────────────────────────────────────
        // Determine a user-friendly message; hide raw exception details.
        final String errorMessage = e.toString().toLowerCase().contains('internet') ||
                e.toString().toLowerCase().contains('network') ||
                e.toString().toLowerCase().contains('connection') ||
                e.toString().toLowerCase().contains('timeout')
            ? 'No internet connection. Please check your network and try again.'
            : "We couldn't reach the server. Please check your connection and try again.";

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: const Color(0xFFB71C1C),
            content: Row(
              children: [
                const Text('⚠️', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Verification Failed',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        errorMessage,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LatLng pickup = LatLng(widget.pickupLat, widget.pickupLng);
    final LatLng dropoff = LatLng(widget.dropoffLat, widget.dropoffLng);

    final Set<Marker> markers = {
      Marker(markerId: const MarkerId('pickup'), position: pickup, infoWindow: const InfoWindow(title: 'Pickup')),
      Marker(markerId: const MarkerId('dropoff'), position: dropoff, infoWindow: const InfoWindow(title: 'Dropoff'), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue)),
    };

    final Set<Polyline> polylines = {
      Polyline(
        polylineId: const PolylineId('route'),
        points: [pickup, dropoff],
        color: AppColors.gold,
        width: 4,
      ),
    };

    // calculate bounds to fit both points
    double minLat = math.min(widget.pickupLat, widget.dropoffLat);
    double maxLat = math.max(widget.pickupLat, widget.dropoffLat);
    double minLng = math.min(widget.pickupLng, widget.dropoffLng);
    double maxLng = math.max(widget.pickupLng, widget.dropoffLng);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Verification'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2),
                zoom: 12,
              ),
              markers: markers,
              polylines: polylines,
              onMapCreated: (controller) {
                // Future.delayed to ensure map is laid out
                Future.delayed(const Duration(milliseconds: 500), () {
                  controller.animateCamera(CameraUpdate.newLatLngBounds(
                    LatLngBounds(
                      southwest: LatLng(minLat - 0.01, minLng - 0.01),
                      northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
                    ),
                    50.0,
                  ));
                });
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Distance:', style: TextStyle(fontSize: 16, color: Colors.grey)),
                    Text('${_distanceKm.toStringAsFixed(2)} km', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Dynamic Price (500/km):', style: TextStyle(fontSize: 16, color: Colors.grey)),
                    Text('TZS ${_totalPrice.toStringAsFixed(0)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.gold)),
                  ],
                ),
                if (widget.suggestedPrice != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Your Offer:', style: TextStyle(fontSize: 16, color: Colors.grey)),
                      Text('TZS ${widget.suggestedPrice?.toStringAsFixed(0)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                CustomButton(
                  text: 'Confirm & Place Order',
                  isLoading: _isSubmitting,
                  onPressed: _submitOrder,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
