import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../delivery/presentation/screens/delivery_detail_screen.dart';
import '../../../orders/providers/order_provider.dart';

class CourierMapFeedScreen extends ConsumerStatefulWidget {
  const CourierMapFeedScreen({super.key});

  @override
  ConsumerState<CourierMapFeedScreen> createState() => _CourierMapFeedScreenState();
}

class _CourierMapFeedScreenState extends ConsumerState<CourierMapFeedScreen> {
  final LocationService _locationService = LocationService();
  GoogleMapController? _mapController;
  LatLng _currentLatLng = const LatLng(-6.7924, 39.2083);
  Set<Marker> _markers = {};
  List<OrderModel> _nearbyOrders = [];
  bool _isLoading = true;
  bool _showMap = true; // Toggle between map and list view
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _locationService.stopLocationStream();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final position = await _locationService.getCurrentLocation();
    if (position != null && mounted) {
      setState(() {
        _currentLatLng = LatLng(position.latitude, position.longitude);
      });
      _mapController?.animateCamera(CameraUpdate.newLatLng(_currentLatLng));
    }

    _locationService.startLocationStream((pos) {
      if (mounted) {
        setState(() {
          _currentLatLng = LatLng(pos.latitude, pos.longitude);
        });
      }
    });

    _fetchNearbyOrders();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _fetchNearbyOrders();
    });
  }

  Future<void> _fetchNearbyOrders() async {
    try {
      final repo = ref.read(orderRepositoryProvider);
      final orders = await repo.getNearbyOrders(
        _currentLatLng.latitude,
        _currentLatLng.longitude,
      );

      if (mounted) {
        setState(() {
          _nearbyOrders = orders;
          _isLoading = false;
          _buildMarkers();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _buildMarkers() {
    final markers = <Marker>{};

    markers.add(
      Marker(
        markerId: const MarkerId('my_location'),
        position: _currentLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'You are here'),
      ),
    );

    for (final order in _nearbyOrders) {
      if (order.pickupLatitude != 0 && order.pickupLongitude != 0) {
        markers.add(
          Marker(
            markerId: MarkerId('order_${order.id}'),
            position: LatLng(order.pickupLatitude!, order.pickupLongitude!),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              order.status == 'PENDING' ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueGreen,
            ),
            infoWindow: InfoWindow(
              title: order.itemType,
              snippet: 'TZS ${order.displayPrice.toStringAsFixed(0)} • ${order.statusLabel}',
            ),
            onTap: () => _showOrderBottomSheet(order),
          ),
        );
      }
    }

    setState(() => _markers = markers);
  }

  void _showOrderBottomSheet(OrderModel order) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_shipping, color: AppColors.navy),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.itemType, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(order.statusLabel, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    ],
                  ),
                ),
                Text(
                  'TZS ${order.displayPrice.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navy),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildAddressRow(Icons.location_on, 'Pickup', order.pickupAddress, Colors.green),
            const SizedBox(height: 8),
            _buildAddressRow(Icons.flag, 'Dropoff', order.dropoffAddress, AppColors.gold),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DeliveryDetailScreen(orderId: order.id)),
                  );
                  _fetchNearbyOrders();
                },
                child: const Text('View Details & Accept', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressRow(IconData icon, String label, String address, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Expanded(
          child: Text(address, style: const TextStyle(color: Colors.grey), overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Orders'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_showMap ? Icons.list : Icons.map),
            tooltip: _showMap ? 'Switch to List View' : 'Switch to Map View',
            onPressed: () {
              setState(() => _showMap = !_showMap);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchNearbyOrders,
          ),
        ],
      ),
      body: _showMap ? Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentLatLng,
              zoom: 14.0,
            ),
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: false,
            onMapCreated: (controller) => _mapController = controller,
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.delivery_dining, color: AppColors.gold),
                  const SizedBox(width: 12),
                  Text(
                    _isLoading
                        ? 'Scanning nearby orders...'
                        : '${_nearbyOrders.length} order${_nearbyOrders.length == 1 ? '' : 's'} nearby',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const Spacer(),
                  if (_isLoading)
                    const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                    ),
                ],
              ),
            ),
          ),
        ],
      ) : _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _nearbyOrders.length,
              itemBuilder: (context, index) {
                final order = _nearbyOrders[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: const Icon(Icons.local_shipping, color: AppColors.navy),
                    title: Text(order.itemType),
                    subtitle: Text('Pickup: ${order.pickupAddress}\nDropoff: ${order.dropoffAddress}'),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                      ),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DeliveryDetailScreen(orderId: order.id)),
                        );
                        _fetchNearbyOrders();
                      },
                      child: const Text('View'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
