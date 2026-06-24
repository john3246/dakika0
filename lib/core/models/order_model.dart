// ─── core/models/order_model.dart ────────────────────────────────────────────
class OrderModel {
  final String id;
  final String customerId;
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

  // Pricing
  final double estimatedPrice;
  final double? suggestedPrice;

  // Cancel
  final String? cancelReason;

  // Timestamps
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? completedAt;

  // Joined fields
  final String? customerName;
  final String? customerPhone;
  final double? customerRating;
  final String? courierName;
  final String? courierPhone;
  final double? courierRating;
  final bool? courierIsVerified;
  final double? courierLatitude;
  final double? courierLongitude;

  const OrderModel({
    required this.id,
    required this.customerId,
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
    required this.estimatedPrice,
    this.suggestedPrice,
    this.cancelReason,
    required this.createdAt,
    this.acceptedAt,
    this.pickedUpAt,
    this.completedAt,
    this.customerName,
    this.customerPhone,
    this.customerRating,
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

  /// Display price: use suggestedPrice if the sender set one, otherwise estimatedPrice.
  double get displayPrice => suggestedPrice ?? estimatedPrice;

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id:             json['id']         as String,
      customerId:     json['customerId'] as String,
      courierId:      json['courierId']  as String?,
      status:         json['status']     as String,

      pickupAddress:   json['pickupAddress']   as String,
      pickupLatitude:  (json['pickupLatitude']  as num?)?.toDouble() ?? 0.0,
      pickupLongitude: (json['pickupLongitude'] as num?)?.toDouble() ?? 0.0,

      dropoffAddress:   json['dropoffAddress']   as String,
      dropoffLatitude:  (json['dropoffLatitude']  as num?)?.toDouble() ?? 0.0,
      dropoffLongitude: (json['dropoffLongitude'] as num?)?.toDouble() ?? 0.0,

      itemType:         json['itemType']         as String,
      itemDescription:  json['itemDescription']  as String?,
      packageWeightKg:  json['packageWeightKg'] != null ? double.tryParse(json['packageWeightKg'].toString()) : null,
      estimatedPrice:   double.tryParse(json['estimatedPrice'].toString()) ?? 0.0,
      suggestedPrice:   json['suggestedPrice'] != null ? double.tryParse(json['suggestedPrice'].toString()) : null,
      cancelReason:     json['cancelReason']     as String?,

      createdAt:   DateTime.parse(json['createdAt']  as String),
      acceptedAt:  json['acceptedAt']  != null ? DateTime.parse(json['acceptedAt']  as String) : null,
      pickedUpAt:  json['pickedUpAt']  != null ? DateTime.parse(json['pickedUpAt']  as String) : null,
      completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt'] as String) : null,

      customerName:      json['customerName']      as String?,
      customerPhone:     json['customerPhone']     as String?,
      customerRating:    json['customerRating'] != null ? double.tryParse(json['customerRating'].toString()) : null,
      courierName:       json['courierName']       as String?,
      courierPhone:      json['courierPhone']      as String?,
      courierRating:     json['courierRating'] != null ? double.tryParse(json['courierRating'].toString()) : null,
      courierIsVerified: json['courierIsVerified'] as bool?,
      courierLatitude:   (json['courierLatitude']  as num?)?.toDouble(),
      courierLongitude:  (json['courierLongitude'] as num?)?.toDouble(),
    );
  }
}
