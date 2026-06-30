import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/models/user_model.dart';
import '../../../../core/models/order_model.dart';

class AdminRepository {
  final ApiClient _apiClient;

  const AdminRepository(this._apiClient);

  Future<Map<String, dynamic>> getStats() async {
    try {
      final response = await _apiClient.dio.get('/admin/stats');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  Future<List<UserModel>> getUsers() async {
    try {
      final response = await _apiClient.dio.get('/admin/users');
      final list = response.data['users'] as List<dynamic>;
      return list.map((e) => UserModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  Future<List<UserModel>> getCouriers() async {
    try {
      final response = await _apiClient.dio.get('/admin/couriers');
      final list = response.data['couriers'] as List<dynamic>;
      return list.map((e) => UserModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  Future<UserModel> updateUserRole(String id, String role) async {
    try {
      final response = await _apiClient.dio.patch('/admin/users/$id/role', data: {'role': role});
      return UserModel.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  Future<UserModel> toggleUserActive(String id, bool isActive) async {
    try {
      final response = await _apiClient.dio.patch('/admin/users/$id/active', data: {'isActive': isActive});
      return UserModel.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  Future<UserModel> verifyCourier(String id, bool approve) async {
    try {
      final response = await _apiClient.dio.post('/admin/couriers/$id/verify', data: {'approve': approve});
      return UserModel.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  Future<List<OrderModel>> getOrders() async {
    try {
      final response = await _apiClient.dio.get('/admin/orders');
      final list = response.data['orders'] as List<dynamic>;
      return list.map((e) => OrderModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  Future<OrderModel> cancelOrder(String id) async {
    try {
      final response = await _apiClient.dio.post('/admin/orders/$id/cancel');
      return OrderModel.fromJson(response.data['order'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }
}
