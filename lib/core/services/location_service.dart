import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;

  Position? get currentPosition => _currentPosition;

  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<Position?> getCurrentLocation() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;

    _currentPosition = await Geolocator.getCurrentPosition();
    return _currentPosition;
  }

  /// Converts GPS coordinates to a human-readable address string.
  ///
  /// Returns the most specific available descriptor: tries
  /// "street name, sub-locality" first, then falls back to
  /// "locality (city)", then a raw "lat, lng" string as last resort.
  Future<String> getAddressFromCoordinates(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return '$lat, $lng';

      final p = placemarks.first;

      // Build a clean, short address from the most specific parts available
      final parts = <String>[
        if (p.name != null && p.name!.isNotEmpty && p.name != p.thoroughfare) p.name!,
        if (p.thoroughfare != null && p.thoroughfare!.isNotEmpty) p.thoroughfare!,
        if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality!,
        if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
      ];

      if (parts.isEmpty) return '$lat, $lng';
      // Return up to two most-specific parts for brevity on the form field
      return parts.take(2).join(', ');
    } catch (_) {
      // Geocoding failed (no network, no result) — fall back to coordinates
      return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    }
  }

  void startLocationStream(void Function(Position) onData) async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return;

    final locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // meters
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      _currentPosition = position;
      onData(position);
    });
  }

  void stopLocationStream() {
    _positionStream?.cancel();
    _positionStream = null;
  }
}

