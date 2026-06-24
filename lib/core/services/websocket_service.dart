import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'location_service.dart';

final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  return WebSocketService();
});

class WebSocketService {
  WebSocket? _socket;
  Timer? _reconnectTimer;
  bool _isConnecting = false;
  String? _token;
  StreamSubscription? _locationSubscription;
  final LocationService _locationService = LocationService();

  // Stream controller to expose incoming events to other parts of the app
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  bool get isConnected => _socket != null && _socket!.readyState == WebSocket.open;

  /// Connect to the WebSocket server with the authentication token
  Future<void> connect(String token) async {
    if (_socket != null || _isConnecting) return;
    _token = token;
    _isConnecting = true;

    // Convert http:// to ws://
    String wsUrl = ApiConstants.baseUrl
        .replaceAll('http://', 'ws://')
        .replaceAll('https://', 'wss://')
        .replaceAll('/api', ''); // remove /api path

    final uri = Uri.parse('$wsUrl?token=$token');
    if (kDebugMode) {
      print('[WS] Connecting to $uri');
    }

    try {
      _socket = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 10));
      _isConnecting = false;
      if (kDebugMode) {
        print('[WS] Connected successfully');
      }

      _reconnectTimer?.cancel();
      _reconnectTimer = null;

      // Start listening to incoming messages
      _socket!.listen(
        (message) {
          _handleIncomingMessage(message);
        },
        onError: (err) {
          if (kDebugMode) print('[WS] Socket error: $err');
          _handleDisconnect();
        },
        onDone: () {
          if (kDebugMode) print('[WS] Socket closed');
          _handleDisconnect();
        },
      );

      // Start periodic location stream to keep server updated with coordinates
      _startLocationTracking();

    } catch (e) {
      _isConnecting = false;
      if (kDebugMode) print('[WS] Connection failed: $e');
      _scheduleReconnect();
    }
  }

  /// Disconnect the socket and cancel any listeners/timers
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopLocationTracking();
    _socket?.close();
    _socket = null;
    _token = null;
    if (kDebugMode) {
      print('[WS] Disconnected manually');
    }
  }

  void _handleIncomingMessage(dynamic message) {
    try {
      final Map<String, dynamic> data = jsonDecode(message as String);
      _eventController.add(data);
    } catch (e) {
      if (kDebugMode) print('[WS] Error parsing message: $e');
    }
  }

  void _handleDisconnect() {
    _socket = null;
    _stopLocationTracking();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null || _token == null) return;
    if (kDebugMode) {
      print('[WS] Scheduling reconnection in 5 seconds...');
    }
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_token != null) {
        connect(_token!);
      }
    });
  }

  /// Start streaming locations to the server if permission is granted
  void _startLocationTracking() async {
    _stopLocationTracking();

    final hasPermission = await _locationService.requestPermission();
    if (!hasPermission) return;

    // Send initial location
    final initialPosition = await _locationService.getCurrentLocation();
    if (initialPosition != null) {
      _sendLocation(initialPosition.latitude, initialPosition.longitude);
    }

    // Subscribe to periodic location stream
    _locationService.startLocationStream((position) {
      _sendLocation(position.latitude, position.longitude);
    });
  }

  void _stopLocationTracking() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _locationService.stopLocationStream();
  }

  void _sendLocation(double lat, double lng) {
    if (!isConnected) return;
    final payload = {
      'type': 'location_update',
      'latitude': lat,
      'longitude': lng,
    };
    _socket!.add(jsonEncode(payload));
  }
}
