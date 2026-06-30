// ─── core/models/order_model.dart ────────────────────────────────────────────
class OrderModel {
  final String id;
  final String creatorId; // Renamed from customerId
  final String? courierId;
  final String status;

  // Pickup
  final String pickupAddress;
  final double pickupLatitude;
  final double pickupLongitude;

  // Dropoff
  final String dropoffAddress;
  final double dropoffLatitude;
  final double dropoffLongitude;

  // Package
  final String itemType;
  final String? itemDescription;
  final double? packageWeightKg;

  // Pricing and Distance
  final double? distanceKm;
  final double totalPrice;
  final double? suggestedPrice;

  // QR and Handoff
  final String? qrCodeSecureString;
  final DateTime? handoffEstimatedTime;

  // Cancel
  final String? cancelReason;

  // Timestamps
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? completedAt;

  // Joined fields
  final String? creatorName;
  final String? creatorPhone;
  final double? creatorRating;
  final String? courierName;
  final String? courierPhone;
  final double? courierRating;
  final bool? courierIsVerified;
  final double? courierLatitude;
  final double? courierLongitude;

  const OrderModel({
    required this.id,
    required this.creatorId,
    this.courierId,
    required this.status,
    required this.pickupAddress,
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.dropoffAddress,
    required this.dropoffLatitude,
    required this.dropoffLongitude,
    required this.itemType,
    this.itemDescription,
    this.packageWeightKg,
    this.distanceKm,
    required this.totalPrice,
    this.suggestedPrice,
    this.qrCodeSecureString,
    this.handoffEstimatedTime,
    this.cancelReason,
    required this.createdAt,
    this.acceptedAt,
    this.pickedUpAt,
    this.completedAt,
    this.creatorName,
    this.creatorPhone,
    this.creatorRating,
    this.courierName,
    this.courierPhone,
    this.courierRating,
    this.courierIsVerified,
    this.courierLatitude,
    this.courierLongitude,
  });

  bool get isActive => status == 'ACCEPTED' || status == 'PICKED_UP';

  String get statusLabel {
    switch (status) {
      case 'PENDING':   return 'Pending';
      case 'ACCEPTED':  return 'Accepted';
      case 'PICKED_UP': return 'In Transit';
      case 'DELIVERED': return 'Delivered';
      case 'CANCELLED': return 'Cancelled';
      default:          return status;
    }
  }

  /// Display price: use suggestedPrice if the sender set one, otherwise totalPrice.
  double get displayPrice => suggestedPrice ?? totalPrice;

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    // Helper: safely parse a DateTime string, returning a fallback if null/invalid.
    DateTime _parseDate(dynamic val, {DateTime? fallback}) {
      if (val == null) return fallback ?? DateTime.now();
      try { return DateTime.parse(val as String); } catch (_) { return fallback ?? DateTime.now(); }
    }

    return OrderModel(
      id:             (json['id'] as String?) ?? '',
      creatorId:      (json['creatorId'] as String?) ?? '',
      courierId:      json['courierId'] as String?,
      // DB stores lowercase; normalise to UPPER for status comparisons throughout the app.
      status:         ((json['status'] as String?) ?? 'PENDING').toUpperCase(),

      pickupAddress:   (json['pickupAddress']  as String?) ?? '',
      pickupLatitude:  (json['pickupLatitude']  as num?)?.toDouble() ?? 0.0,
      pickupLongitude: (json['pickupLongitude'] as num?)?.toDouble() ?? 0.0,

      dropoffAddress:   (json['dropoffAddress']   as String?) ?? '',
      dropoffLatitude:  (json['dropoffLatitude']  as num?)?.toDouble() ?? 0.0,
      dropoffLongitude: (json['dropoffLongitude'] as num?)?.toDouble() ?? 0.0,

      itemType:         (json['itemType']        as String?) ?? 'Package',
      itemDescription:  json['itemDescription'] as String?,
      packageWeightKg:  json['packageWeightKg'] != null
          ? double.tryParse(json['packageWeightKg'].toString())
          : null,
      distanceKm:       json['distanceKm'] != null
          ? double.tryParse(json['distanceKm'].toString())
          : null,
      totalPrice:       double.tryParse(json['totalPrice']?.toString() ?? '0') ?? 0.0,
      suggestedPrice:   json['suggestedPrice'] != null
          ? double.tryParse(json['suggestedPrice'].toString())
          : null,
      qrCodeSecureString: json['qrCodeSecureString'] as String?,
      handoffEstimatedTime: json['handoffEstimatedTime'] != null
          ? _parseDate(json['handoffEstimatedTime'])
          : null,
      cancelReason:     json['cancelReason'] as String?,

      createdAt:   _parseDate(json['createdAt']),
      acceptedAt:  json['acceptedAt']  != null ? _parseDate(json['acceptedAt'])  : null,
      pickedUpAt:  json['pickedUpAt']  != null ? _parseDate(json['pickedUpAt'])  : null,
      completedAt: json['completedAt'] != null ? _parseDate(json['completedAt']) : null,

      creatorName:       json['creatorName']  as String?,
      creatorPhone:      json['creatorPhone'] as String?,
      creatorRating:     json['creatorRating'] != null
          ? double.tryParse(json['creatorRating'].toString())
          : null,
      courierName:       json['courierName']  as String?,
      courierPhone:      json['courierPhone'] as String?,
      courierRating:     json['courierRating'] != null
          ? double.tryParse(json['courierRating'].toString())
          : null,
      courierIsVerified: json['courierIsVerified'] as bool?,
      courierLatitude:   (json['courierLatitude']  as num?)?.toDouble(),
      courierLongitude:  (json['courierLongitude'] as num?)?.toDouble(),
    );
  }
}
