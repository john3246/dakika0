import 'dart:io';
import 'package:dio/dio.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';

class ProfileRepository {
  final ApiClient _apiClient;

  ProfileRepository(this._apiClient);

  Future<Map<String, dynamic>> getProfile() async {
    try {
      final response = await _apiClient.dio.get(ApiConstants.profileEndpoint);
      return response.data['profile'];
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    try {
      final response = await _apiClient.dio.put(ApiConstants.profileUpdateEndpoint, data: data);
      return response.data['profile'];
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }

  Future<Map<String, dynamic>> upgradeCourier(Map<String, dynamic> data) async {
    try {
      final response = await _apiClient.dio.post(ApiConstants.upgradeCourierEndpoint, data: data);
      return response.data['profile'];
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.response?.data['error'] ?? e.message);
    }
  }

  Future<String> uploadDocument(File file, {String type = 'profile'}) async {
    try {
      String fileName = file.path.split('/').last;
      FormData formData = FormData.fromMap({
        "document": await MultipartFile.fromFile(file.path, filename: fileName),
      });

      final response = await _apiClient.dio.post(
        '${ApiConstants.documentUploadEndpoint}?type=$type',
        data: formData,
      );
      return response.data['url'];
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message);
    }
  }
}
