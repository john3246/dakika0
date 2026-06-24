import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class RealTimeMapScreen extends StatefulWidget {
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final double? courierLat;
  final double? courierLng;

  const RealTimeMapScreen({
    Key? key,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    this.courierLat,
    this.courierLng,
  }) : super(key: key);

  @override
  State<RealTimeMapScreen> createState() => _RealTimeMapScreenState();
}

class _RealTimeMapScreenState extends State<RealTimeMapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  late CameraPosition _initialPosition;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _initialPosition = CameraPosition(
      target: LatLng(widget.pickupLat, widget.pickupLng),
      zoom: 14.0,
    );
    _setupMarkers();
  }

  void _setupMarkers() {
    _markers.add(
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(widget.pickupLat, widget.pickupLng),
        infoWindow: const InfoWindow(title: 'Pickup Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    );

    _markers.add(
      Marker(
        markerId: const MarkerId('dropoff'),
        position: LatLng(widget.dropoffLat, widget.dropoffLng),
        infoWindow: const InfoWindow(title: 'Dropoff Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    );

    if (widget.courierLat != null && widget.courierLng != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('courier'),
          position: LatLng(widget.courierLat!, widget.courierLng!),
          infoWindow: const InfoWindow(title: 'Courier'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    _polylines.add(
      Polyline(
        polylineId: const PolylineId('route'),
        points: [
          if (widget.courierLat != null && widget.courierLng != null)
            LatLng(widget.courierLat!, widget.courierLng!),
          LatLng(widget.pickupLat, widget.pickupLng),
          LatLng(widget.dropoffLat, widget.dropoffLng),
        ],
        color: Colors.blueAccent,
        width: 4,
      ),
    );
  }

  Future<void> _centerView() async {
    final GoogleMapController controller = await _controller.future;
    
    LatLngBounds bounds;
    final List<LatLng> points = [
      LatLng(widget.pickupLat, widget.pickupLng),
      LatLng(widget.dropoffLat, widget.dropoffLng),
      if (widget.courierLat != null && widget.courierLng != null)
        LatLng(widget.courierLat!, widget.courierLng!)
    ];

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Tracking')),
      body: GoogleMap(
        mapType: MapType.normal,
        initialCameraPosition: _initialPosition,
        markers: _markers,
        polylines: _polylines,
        onMapCreated: (GoogleMapController controller) {
          _controller.complete(controller);
          Future.delayed(const Duration(milliseconds: 500), _centerView);
        },
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _centerView,
        child: const Icon(Icons.center_focus_strong),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }
}
