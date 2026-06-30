// ─── core/models/user_model.dart ─────────────────────────────────────────────
class UserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String courierStatus; // 'unverified', 'pending', 'verified'
  final bool isFullyVerified;
  final String? profileImageUrl;
  final double senderRating;
  final double courierRating;
  
  final String? nidaNumber;
  final String? nidaDocumentUrl;
  final String? selfieUrl;
  final String? vehicleType;
  final String? vehicleRegistrationNumber;
  
  final String role;
  final bool isActive;
  final DateTime? createdAt;
  final bool? isVerified;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.courierStatus,
    required this.isFullyVerified,
    this.profileImageUrl,
    required this.senderRating,
    required this.courierRating,
    this.nidaNumber,
    this.nidaDocumentUrl,
    this.selfieUrl,
    this.vehicleType,
    this.vehicleRegistrationNumber,
    this.role = 'CUSTOMER',
    this.isActive = true,
    this.createdAt,
    this.isVerified,
  });

  bool get isVerifiedCourier => isFullyVerified && courierStatus == 'verified';

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id:               json['id'] as String,
      name:             json['name'] as String,
      email:            json['email'] as String,
      phone:            json['phone'] as String,
      courierStatus:    json['courierStatus'] as String? ?? 'unverified',
      isFullyVerified:  json['isFullyVerified'] as bool? ?? false,
      profileImageUrl:  json['profileImageUrl'] as String?,
      senderRating:     json['senderRating'] != null ? double.tryParse(json['senderRating'].toString()) ?? 5.0 : 5.0,
      courierRating:    json['courierRating'] != null ? double.tryParse(json['courierRating'].toString()) ?? 5.0 : 5.0,
      nidaNumber:       json['nidaNumber'] as String?,
      nidaDocumentUrl:  json['nidaDocumentUrl'] as String?,
      selfieUrl:        json['selfieUrl'] as String?,
      vehicleType:      json['vehicleType'] as String?,
      vehicleRegistrationNumber: json['vehicleRegistrationNumber'] as String?,
      role:             json['role'] as String? ?? 'CUSTOMER',
      isActive:         json['isActive'] as bool? ?? true,
      createdAt:        json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
      isVerified:       json['isVerified'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id':              id,
    'name':            name,
    'email':           email,
    'phone':           phone,
    'courierStatus':   courierStatus,
    'isFullyVerified': isFullyVerified,
    'profileImageUrl': profileImageUrl,
    'senderRating':    senderRating,
    'courierRating':   courierRating,
    'nidaNumber':      nidaNumber,
    'nidaDocumentUrl': nidaDocumentUrl,
    'selfieUrl':       selfieUrl,
    'vehicleType':     vehicleType,
    'vehicleRegistrationNumber': vehicleRegistrationNumber,
    'role':            role,
    'isActive':        isActive,
    'createdAt':       createdAt?.toIso8601String(),
    'isVerified':      isVerified,
  };

  UserModel copyWith({
    String? name,
    String? phone,
    String? courierStatus,
    bool? isFullyVerified,
    String? profileImageUrl,
  }) {
    return UserModel(
      id:              id,
      name:            name ?? this.name,
      email:           email,
      phone:           phone ?? this.phone,
      courierStatus:   courierStatus ?? this.courierStatus,
      isFullyVerified: isFullyVerified ?? this.isFullyVerified,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      senderRating:    senderRating,
      courierRating:   courierRating,
      nidaNumber:      nidaNumber ?? this.nidaNumber,
      nidaDocumentUrl: nidaDocumentUrl ?? this.nidaDocumentUrl,
      selfieUrl:       selfieUrl ?? this.selfieUrl,
      vehicleType:     vehicleType ?? this.vehicleType,
      vehicleRegistrationNumber: vehicleRegistrationNumber ?? this.vehicleRegistrationNumber,
    );
  }
}
