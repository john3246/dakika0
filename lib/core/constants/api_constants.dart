import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConstants {
  static String get baseUrl => dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000/api';

  // ── Auth ──────────────────────────────────────────────────────────────────
  static const String loginEndpoint              = '/auth/login';
  static const String registerEndpoint           = '/auth/register';

  // ── Profile ───────────────────────────────────────────────────────────────
  static const String profileEndpoint            = '/profile/me';
  static const String profileUpdateEndpoint      = '/profile/update';
  static const String documentUploadEndpoint     = '/profile/upload-document';
  static const String upgradeCourierEndpoint     = '/profile/upgrade-courier';

  // ── Orders ────────────────────────────────────────────────────────────────
  static const String ordersEndpoint             = '/orders';
  static const String myOrdersEndpoint           = '/orders/mine';
  static const String availableOrdersEndpoint    = '/orders/available';
  static const String orderStatsEndpoint         = '/orders/stats';
}
