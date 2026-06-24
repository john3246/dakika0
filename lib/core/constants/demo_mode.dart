import '../models/order_model.dart';
import '../models/user_model.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// PRESENTATION / DEMO MODE
/// Set [kDemoMode] to true to skip ALL authentication checks and use mock data.
/// Remember to set it back to false before a real release.
/// ─────────────────────────────────────────────────────────────────────────────
const bool kDemoMode = true;

// ── Mock User ────────────────────────────────────────────────────────────────
final UserModel kDemoUser = UserModel(
  id: 'demo-001',
  name: 'John Raphael',
  email: 'demo@dakika0.com',
  phone: '+255712345678',
  courierStatus: 'verified',
  isFullyVerified: true,
  profileImageUrl: null,
  senderRating: 4.8,
  courierRating: 4.9,
  nidaNumber: '19900101-12345-00001-6',
  nidaDocumentUrl: null,
  selfieUrl: null,
  vehicleType: 'Motorcycle',
  vehicleRegistrationNumber: 'T123 ABC',
);

// ── Mock Orders ──────────────────────────────────────────────────────────────
final List<OrderModel> kDemoActiveOrders = [
  OrderModel(
    id: 'order-001',
    customerId: 'demo-001',
    courierId: 'courier-42',
    status: 'ACCEPTED',
    pickupAddress: 'Kariakoo Market, Dar es Salaam',
    pickupLatitude: -6.8161,
    pickupLongitude: 39.2694,
    dropoffAddress: 'Mlimani City Mall, Dar es Salaam',
    dropoffLatitude: -6.7726,
    dropoffLongitude: 39.2381,
    itemType: 'Electronics',
    itemDescription: 'Laptop – handle with care',
    packageWeightKg: 2.5,
    estimatedPrice: 8500,
    createdAt: DateTime.now().subtract(const Duration(minutes: 18)),
    acceptedAt: DateTime.now().subtract(const Duration(minutes: 12)),
    customerName: 'John Raphael',
    customerPhone: '+255712345678',
    courierName: 'Baraka Juma',
    courierPhone: '+255754321987',
    courierIsVerified: true,
    courierLatitude: -6.800,
    courierLongitude: 39.260,
  ),
  OrderModel(
    id: 'order-002',
    customerId: 'demo-001',
    courierId: null,
    status: 'PENDING',
    pickupAddress: 'Mwenge Bus Stand, Dar es Salaam',
    pickupLatitude: -6.7711,
    pickupLongitude: 39.2333,
    dropoffAddress: 'Sinza Roundabout, Dar es Salaam',
    dropoffLatitude: -6.7832,
    dropoffLongitude: 39.2451,
    itemType: 'Documents',
    itemDescription: 'Legal papers – urgent',
    packageWeightKg: 0.3,
    estimatedPrice: 4000,
    createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
    customerName: 'John Raphael',
    customerPhone: '+255712345678',
  ),
];

final List<OrderModel> kDemoAvailableOrders = [
  OrderModel(
    id: 'order-003',
    customerId: 'customer-99',
    status: 'PENDING',
    pickupAddress: 'Posta, Dar es Salaam',
    pickupLatitude: -6.8120,
    pickupLongitude: 39.2822,
    dropoffAddress: 'Tegeta, Dar es Salaam',
    dropoffLatitude: -6.6920,
    dropoffLongitude: 39.2233,
    itemType: 'Clothing',
    estimatedPrice: 6500,
    createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
    customerName: 'Fatuma Said',
    customerPhone: '+255712000001',
  ),
  OrderModel(
    id: 'order-004',
    customerId: 'customer-55',
    status: 'PENDING',
    pickupAddress: 'Ubungo Terminal, Dar es Salaam',
    pickupLatitude: -6.7927,
    pickupLongitude: 39.2247,
    dropoffAddress: 'Msasani Peninsula, Dar es Salaam',
    dropoffLatitude: -6.7558,
    dropoffLongitude: 39.2780,
    itemType: 'Food & Groceries',
    itemDescription: 'Fragile – keep upright',
    estimatedPrice: 5200,
    createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
    customerName: 'Hassan Ali',
    customerPhone: '+255754999888',
  ),
];

final Map<String, int> kDemoStats = {
  'DELIVERED': 14,
  'CANCELLED': 2,
};

