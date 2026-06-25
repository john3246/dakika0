import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/models/user_model.dart';
import '../../../../core/network/api_client.dart';

const _kAuthToken  = 'auth_token';
const _kUserJson   = 'user_json';

class AuthRepository {
  final ApiClient _apiClient;

  AuthRepository(this._apiClient);

  // ── Login ──────────────────────────────────────────────────────────────────
  Future<UserModel> login(String identifier, String password, {bool isEmail = true}) async {

    try {
      final payload = isEmail
          ? {'email': identifier, 'password': password}
          : {'phone': identifier, 'password': password};

      final response = await _apiClient.dio.post(ApiConstants.loginEndpoint, data: payload);

      if (response.statusCode == 200) {
        final token = response.data['accessToken'] as String;
        final user  = UserModel.fromJson(response.data['user'] as Map<String, dynamic>);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kAuthToken, token);
        await prefs.setString(_kUserJson, jsonEncode(user.toJson()));

        return user;
      }
      throw Exception('Login failed');
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  // ── Unified Register ───────────────────────────────────────────────────────
  Future<void> register(String name, String email, String phone, String password) async {
    try {
      final payload = {'name': name, 'email': email, 'phone': phone, 'password': password};
      final response = await _apiClient.dio.post(ApiConstants.registerEndpoint, data: payload);
      if (response.statusCode != 201) throw Exception('Registration failed');
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  // ── Logout ─────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAuthToken);
    await prefs.remove(_kUserJson);
  }

  // ── Token check (Live Verification) ────────────────────────────────────────
  Future<bool> isAuthenticated() async {

    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kAuthToken)) return false;

    try {
      final response = await _apiClient.dio.get(ApiConstants.profileEndpoint);
      return response.statusCode == 200;
    } catch (_) {
      await logout();
      return false;
    }
  }

  // ── Read cached user (no network call) ─────────────────────────────────────
  Future<UserModel?> getStoredUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kUserJson);
    if (raw == null) return null;
    try {
      return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
