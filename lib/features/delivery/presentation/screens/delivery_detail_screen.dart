import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/websocket_service.dart';
import '../../../orders/providers/order_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../orders/presentation/widgets/review_dialog.dart';
import 'sender_qr_screen.dart';
import 'courier_scanner_screen.dart';

class DeliveryDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  const DeliveryDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends ConsumerState<DeliveryDetailScreen> {
  GoogleMapController? _mapController;
  LatLng? _courierLatLng;
  StreamSubscription? _wsSubscription;
  bool _initializedCourierLocation = false;

  @override
  void initState() {
    super.initState();
    _subscribeToLiveTracking();
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _subscribeToLiveTracking() {
    final wsService = ref.read(webSocketServiceProvider);
    _wsSubscription = wsService.eventStream.listen((event) {
      if (event['type'] == 'delivery_location_update' &&
          event['orderId'] == widget.orderId) {
        final lat = event['latitude'] as double?;
        final lng = event['longitude'] as double?;
        if (lat != null && lng != null && mounted) {
          setState(() {
            _courierLatLng = LatLng(lat, lng);
          });
          _mapController?.animateCamera(CameraUpdate.newLatLng(_courierLatLng!));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderId));
    final currentUserAsync = ref.watch(currentUserProvider);
    final currentUserId = currentUserAsync.valueOrNull?.id;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Delivery Details"),
        centerTitle: true,
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Failed to load order', style: Theme.of(context).textTheme.titleMedium),
              TextButton(
                onPressed: () => ref.refresh(orderDetailProvider(widget.orderId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (order) {
          // Initialize courier location from DB if not already initialized
          if (!_initializedCourierLocation) {
            if (order.courierLatitude != null && order.courierLongitude != null) {
              _courierLatLng = LatLng(order.courierLatitude!, order.courierLongitude!);
            }
            _initializedCourierLocation = true;
          }
          return _buildContent(context, order, isDark, currentUserId);
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    OrderModel order,
    bool isDark,
    String? currentUserId,
  ) {
    Color statusColor;
    switch (order.status) {
      case 'PENDING':   statusColor = Colors.orange;      break;
      case 'ACCEPTED':  statusColor = Colors.blue;         break;
      case 'PICKED_UP': statusColor = Colors.deepOrange;   break;
      case 'DELIVERED': statusColor = Colors.green;        break;
      case 'CANCELLED': statusColor = Colors.red;          break;
      default:          statusColor = Colors.grey;
    }

    final showLiveMap = order.status == 'ACCEPTED' || order.status == 'PICKED_UP';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.local_shipping, color: statusColor, size: 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Status: ${order.statusLabel}",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Text(
                        "Order placed ${_formatDate(order.createdAt)}",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn().slideY(begin: 0.1),
          const SizedBox(height: 24),

          // Real-time tracking Map
          if (showLiveMap) ...[
            _buildLiveMapSection(order),
            const SizedBox(height: 24),
          ],

          _buildSectionTitle("Delivery Route"),
          const SizedBox(height: 16),
          _buildRouteStep(
            icon: Icons.location_on,
            color: Colors.green,
            title: "Pickup Location",
            address: order.pickupAddress,
            time: order.pickedUpAt != null
                ? "Picked up at ${_formatDate(order.pickedUpAt!)}"
                : "Awaiting pickup",
          ),
          _buildRouteDivider(),
          _buildRouteStep(
            icon: Icons.flag,
            color: AppColors.gold,
            title: "Destination",
            address: order.dropoffAddress,
            time: order.completedAt != null
                ? "Delivered ${_formatDate(order.completedAt!)}"
                : "Awaiting delivery",
            isLast: true,
          ),
          const SizedBox(height: 30),
          if (order.courierName != null) ...[
            _buildSectionTitle("Courier Information"),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                radius: 25,
                backgroundColor: AppColors.navy,
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: Text(
                order.courierName!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                "${order.courierIsVerified == true ? 'Verified Courier' : 'Courier'}"
                " • ${order.courierRating?.toStringAsFixed(1) ?? '—'} ★",
              ),
              trailing: order.courierPhone != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _launchDialer(order.courierPhone!),
                          icon: const Icon(Icons.phone, color: Colors.green),
                          tooltip: 'Call Courier',
                        ),
                      ],
                    )
                  : null,
            ).animate().fadeIn(delay: 400.ms),
            const SizedBox(height: 30),
          ],
          if (order.creatorName != null && order.creatorPhone != null) ...[
            _buildSectionTitle("Sender Information"),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                radius: 25,
                backgroundColor: AppColors.gold,
                child: Icon(Icons.person_outline, color: AppColors.navy),
              ),
              title: Text(
                order.creatorName!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${order.creatorRating?.toStringAsFixed(1) ?? '5.0'} ★ Sender Rating',
              ),
              trailing: IconButton(
                onPressed: () => _launchDialer(order.creatorPhone!),
                icon: const Icon(Icons.phone, color: Colors.green),
                tooltip: 'Call Sender',
              ),
            ).animate().fadeIn(delay: 500.ms),
            const SizedBox(height: 30),
          ],
          _buildSectionTitle("Order Summary"),
          const SizedBox(height: 16),
          _buildSummaryRow("Item Type", order.itemType),
          if (order.itemDescription != null)
            _buildSummaryRow("Description", order.itemDescription!),
          if (order.packageWeightKg != null)
            _buildSummaryRow("Weight", "${order.packageWeightKg} kg"),
          _buildSummaryRow(
            "Delivery Fee",
            "TZS ${order.displayPrice.toStringAsFixed(0)}",
          ),
          const Divider(height: 32),
          _buildSummaryRow(
            "Total",
            "TZS ${order.displayPrice.toStringAsFixed(0)}",
            isBold: true,
          ),
          if (order.status != 'DELIVERED' && order.status != 'CANCELLED') ...[
            const SizedBox(height: 24),
            // Hide the "Accept Order" action silently if the user is the owner of the order
            // Action for Courier to Accept Order (No QR needed here)
            if (order.status == 'PENDING' && order.creatorId != currentUserId)
              _buildActionButton(context, order, 'ACCEPTED', 'Accept Order', Colors.blue),

            // Action for Courier to Scan QR at Pickup
            if (order.status == 'ACCEPTED' && order.courierId == currentUserId)
              _buildScanButton(context, order, true, 'Scan QR to Pickup', Colors.deepOrange),
              
            // Action for Courier to Scan QR at Dropoff
            if (order.status == 'PICKED_UP' && order.courierId == currentUserId)
              _buildScanButton(context, order, false, 'Scan QR to Complete', Colors.green),

            // Action for Creator to show QR Code to Courier
            if ((order.status == 'ACCEPTED' || order.status == 'PICKED_UP') && order.creatorId == currentUserId)
              _buildShowQrButton(context, order),
          ],
          if (order.status == 'PENDING' || (order.status == 'ACCEPTED' && order.creatorId == currentUserId)) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _cancelOrder(context, order.id),
                child: const Text("Cancel Order", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveMapSection(OrderModel order) {
    final pickup = LatLng(order.pickupLatitude, order.pickupLongitude);
    final dropoff = LatLng(order.dropoffLatitude, order.dropoffLongitude);

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: pickup,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Pickup Location'),
      ),
      Marker(
        markerId: const MarkerId('dropoff'),
        position: dropoff,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: const InfoWindow(title: 'Dropoff Destination'),
      ),
    };

    if (_courierLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('courier'),
          position: _courierLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Courier Live Location'),
        ),
      );
    }

    // Polylines representing direction paths
    final polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('delivery_path'),
        points: [pickup, dropoff],
        color: AppColors.gold,
        width: 3,
        patterns: [PatternItem.dash(12), PatternItem.gap(8)], // Dash pattern for path
      ),
    };

    if (_courierLatLng != null) {
      // Draw line from Courier to their next target
      final target = order.status == 'ACCEPTED' ? pickup : dropoff;
      polylines.add(
        Polyline(
          polylineId: const PolylineId('courier_heading'),
          points: [_courierLatLng!, target],
          color: Colors.blue,
          width: 4,
        ),
      );
    }

    final initialCenter = _courierLatLng ?? pickup;

    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: initialCenter,
            zoom: 13.5,
          ),
          markers: markers,
          polylines: polylines,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          onMapCreated: (controller) {
            _mapController = controller;
            if (_courierLatLng != null) {
              _mapController!.animateCamera(CameraUpdate.newLatLng(_courierLatLng!));
            }
          },
        ),
      ),
    ).animate().fadeIn(delay: 100.ms).scale(begin: const Offset(0.95, 0.95));
  }

  void _invalidateAll(String id) {
    ref.invalidate(orderDetailProvider(id));
    ref.invalidate(myActiveOrdersProvider);
    ref.invalidate(orderStatsProvider);
    ref.invalidate(myOrderHistoryProvider);
    ref.invalidate(availableOrdersProvider);
  }

  Future<void> _cancelOrder(BuildContext context, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Cancel Order"),
        content: const Text("Are you sure you want to cancel this order?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Yes, Cancel", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      final repo = ref.read(orderRepositoryProvider);
      await repo.updateStatus(id, 'CANCELLED');
      _invalidateAll(id);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Widget _buildActionButton(BuildContext context, OrderModel order, String newStatus, String label, Color color) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () async {
          try {
            final repo = ref.read(orderRepositoryProvider);
            await repo.updateStatus(order.id, newStatus);
            _invalidateAll(order.id);
            
            if (context.mounted) {
              if (newStatus == 'DELIVERED') {
                final targetName = order.creatorId == ref.read(currentUserProvider).valueOrNull?.id 
                    ? order.courierName ?? 'Courier' 
                    : order.creatorName ?? 'Sender';
                
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => ReviewDialog(orderId: order.id, targetName: targetName),
                ).then((_) {
                  _invalidateAll(order.id);
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Order status updated to $newStatus')));
              }
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          }
        },
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  static Future<void> _launchDialer(String phoneNumber) async {
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  String _formatDate(DateTime dt) {
    return "${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
  }

  Widget _buildRouteStep({
    required IconData icon,
    required Color color,
    required String title,
    required String address,
    required String time,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(address, style: const TextStyle(color: Colors.grey)),
              Text(time, style: TextStyle(color: color.withOpacity(0.8), fontSize: 12)),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildRouteDivider() {
    return Container(
      margin: const EdgeInsets.only(left: 11, top: 4, bottom: 4),
      height: 30,
      width: 2,
      color: Colors.grey.withOpacity(0.3),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: isBold ? null : Colors.grey)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: isBold ? 18 : 14,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShowQrButton(BuildContext context, OrderModel order) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () {
          if (order.qrCodeSecureString == null) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SenderQrScreen(trackingToken: order.qrCodeSecureString!),
            ),
          );
        },
        icon: const Icon(Icons.qr_code_2),
        label: const Text('Show QR to Courier', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  Widget _buildScanButton(BuildContext context, OrderModel order, bool isPickup, String label, Color color) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CourierScannerScreen(
                title: label,
                onScan: (qrCode) async {
                  Navigator.pop(context); // Close scanner
                  try {
                    final repo = ref.read(orderRepositoryProvider);
                    if (isPickup) {
                      await repo.pickupOrder(order.id, qrCode);
                    } else {
                      await repo.completeOrder(order.id, qrCode);
                    }
                    _invalidateAll(order.id);
                    
                    if (mounted) {
                      if (!isPickup) {
                        // Complete order logic (show review)
                        final targetName = order.creatorId == ref.read(currentUserProvider).valueOrNull?.id 
                            ? order.courierName ?? 'Courier' 
                            : order.creatorName ?? 'Sender';
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => ReviewDialog(orderId: order.id, targetName: targetName),
                        ).then((_) => _invalidateAll(order.id));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order picked up successfully!')));
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Verification Failed: $e', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red));
                    }
                  }
                },
              ),
            ),
          );
        },
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}
