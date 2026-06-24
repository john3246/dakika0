import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';

class ApiClient {
  late final Dio _dio;

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('auth_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) async {
        // Handle global errors here (e.g., 401 Unauthorized -> clear token)
        if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('auth_token');
          await prefs.remove('user_json');
        }
        return handler.next(e);
      },
    ));
  }

  Dio get dio => _dio;

  Future<bool> pingServer() async {
    try {
      final response = await _dio.get('/');
      // If we get any response (even 404), the server is reachable.
      return true;
    } catch (e) {
      if (e is DioException && e.response != null) {
        return true; // Reached server, but got an error like 404
      }
      return false;
    }
  }
}
