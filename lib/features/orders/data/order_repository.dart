// ─── features/orders/data/order_repository.dart ─────────────────────────────
// Single source of truth for all order API calls.
// Consumed by order_provider.dart — never called directly from screens.

import 'package:dio/dio.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/models/order_model.dart';
import '../../../../core/network/api_client.dart';

class OrderRepository {
  final ApiClient _apiClient;

  const OrderRepository(this._apiClient);

  // ── Create a new delivery order ──────────────────────────────────────────
  Future<OrderModel> createOrder({
    required String pickupAddress,
    required String dropoffAddress,
    required String itemType,
    String? itemDescription,
    double? packageWeightKg,
    double? suggestedPrice,
    double pickupLatitude = 0,
    double pickupLongitude = 0,
    double dropoffLatitude = 0,
    double dropoffLongitude = 0,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        ApiConstants.ordersEndpoint,
        data: {
          'pickupAddress':    pickupAddress,
          'pickupLat':        pickupLatitude,
          'pickupLng':        pickupLongitude,
          'dropoffAddress':   dropoffAddress,
          'dropoffLat':       dropoffLatitude,
          'dropoffLng':       dropoffLongitude,
          'itemType':         itemType,
          'itemDescription':  itemDescription,
          'packageWeightKg':  packageWeightKg,
          if (suggestedPrice != null) 'suggestedPrice': suggestedPrice,
        },
      );
      return OrderModel.fromJson(response.data['order'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  // ── Get current user's orders, optionally filtered by status ───────────────
  // statusFilter example: 'ACCEPTED,PICKED_UP'  or  null for all
  Future<List<OrderModel>> getMyOrders({String? statusFilter}) async {

    try {
      final response = await _apiClient.dio.get(
        ApiConstants.myOrdersEndpoint,
        queryParameters: statusFilter != null ? {'status': statusFilter} : null,
      );
      final list = response.data['orders'] as List<dynamic>;
      return list.map((e) => OrderModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  // ── Get PENDING orders available for couriers to accept ──────────────────
  Future<List<OrderModel>> getAvailableOrders() async {

    try {
      final response = await _apiClient.dio.get(ApiConstants.availableOrdersEndpoint);
      final list = response.data['orders'] as List<dynamic>;
      return list.map((e) => OrderModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  // ── Get nearby PENDING/ACCEPTED orders using Geospatial Radius ──────────
  Future<List<OrderModel>> getNearbyOrders(double lat, double lng, {double radiusKm = 10.0}) async {

    try {
      final response = await _apiClient.dio.get(
        '${ApiConstants.ordersEndpoint}/nearby',
        queryParameters: {'lat': lat, 'lng': lng, 'radiusKm': radiusKm},
      );
      final list = response.data['orders'] as List<dynamic>;
      return list.map((e) => OrderModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  // ── Get a single order by ID (with full courier/customer JOIN) ─────────
  Future<OrderModel> getOrderById(String orderId) async {
    try {
      final response = await _apiClient.dio.get('${ApiConstants.ordersEndpoint}/$orderId');
      return OrderModel.fromJson(response.data['order'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  // ── Update order status (state machine) ────────────────────────────────
  Future<OrderModel> updateStatus(String orderId, String status, {String? cancelReason}) async {
    try {
      final response = await _apiClient.dio.patch(
        '${ApiConstants.ordersEndpoint}/$orderId/status',
        data: {
          'status': status,
          if (cancelReason != null) 'cancelReason': cancelReason,
        },
      );
      return OrderModel.fromJson(response.data['order'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  // ── Pickup Order (QR Validation) ──────────────────────────────────────────
  Future<OrderModel> pickupOrder(String orderId, String qrCode) async {
    try {
      final response = await _apiClient.dio.post(
        '${ApiConstants.ordersEndpoint}/$orderId/pickup',
        data: {'qrCodeSecureString': qrCode},
      );
      return OrderModel.fromJson(response.data['order'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  // ── Complete Order (QR Validation) ────────────────────────────────────────
  Future<OrderModel> completeOrder(String orderId, String qrCode) async {
    try {
      final response = await _apiClient.dio.post(
        '${ApiConstants.ordersEndpoint}/$orderId/complete',
        data: {'qrCodeSecureString': qrCode},
      );
      return OrderModel.fromJson(response.data['order'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  // ── Get order count stats for the dashboard ──────────────────────────────
  Future<Map<String, int>> getMyStats() async {

    try {
      final response = await _apiClient.dio.get(ApiConstants.orderStatsEndpoint);
      final raw = response.data['stats'] as Map<String, dynamic>;
      return raw.map((k, v) => MapEntry(k, (v as num).toInt()));
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  // ── Rate an order (customer or courier) ──────────────────────────────────
  Future<void> rateOrder(String orderId, double rating) async {
    try {
      await _apiClient.dio.post(
        '${ApiConstants.ordersEndpoint}/$orderId/rate',
        data: {'rating': rating},
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }
}
