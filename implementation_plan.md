# 6-Feature Implementation Plan

## Background

After thorough codebase research, here is the exact status of each feature and what truly needs to be built vs. what is already done.

## Pre-existing Work (Already Implemented — No Change Needed)

| Feature | Already Done |
|---|---|
| **F1** `google_maps_flutter` | ✅ Used in `order_verification_screen` and `delivery_detail_screen` |
| **F4** `mobile_scanner` package | ✅ Already in `pubspec.yaml: ^5.0.0` |
| **F4** `qr_flutter` package | ✅ Already in `pubspec.yaml: ^4.1.0` |
| **F4** `CourierScannerScreen` wiring | ✅ `delivery_detail_screen.dart` already calls `pickupOrder`/`completeOrder` via scanner |
| **F5** Admin dashboard + CRUD | ✅ `admin_dashboard_screen`, `manage_users_screen`, `manage_orders_screen` all exist and work |
| **F5** Backend admin endpoints | ✅ `adminController.js` has full CRUD for users, couriers, orders |
| **F6** `shared_preferences` | ✅ Already used in `auth_repository.dart` — user JSON is stored on login |
| **F2** JWT `7d` expiry | ✅ Already changed in `authController.js` |

## Real Work Required

### FEATURE 1 — Reverse Geocoding in Request Delivery Screen

**Gap:** `location_service.dart` fetches a GPS `Position` but has no geocoding. `request_delivery_screen.dart` sets `_pickupController.text = "Current GPS Location"` — a hardcoded string, not a real address.

**Plan:**
- Add `geocoding: ^3.0.0` to `pubspec.yaml`
- Extend `LocationService.getCurrentLocation()` with a `getAddressFromCoordinates(lat, lng)` helper
- Update `RequestDeliveryScreen._fetchLocation()` to call geocoding and populate the controller with the actual street/suburb name

---

### FEATURE 2 — Order State Push Notifications

**Gap:** `acceptOrder`, `pickupOrder`, and `completeOrder` in `orderController.js` commit to DB and broadcast via WebSocket but **never send a push notification** to the order creator.

**Plan:**
- Add a `notifyOrderCreator(orderId, status)` helper that looks up `creator_id → device_token` and fires FCM
- Inject that helper call (wrapped in try/catch) into `acceptOrder`, `pickupOrder`, and `completeOrder` — after COMMIT, before the HTTP response

**JWT:** Already `7d`. Extending to `30d` as requested.

---

### FEATURE 3 — Escrow & Wallet System

**Gap:** The DB already has a `wallets` table and `wallet_ledger` table (in `migrate.js`). The `orders` table has no `escrow_balance` column. No controller handles escrow locking or release.

**Plan:**
- Add `ADD COLUMN IF NOT EXISTS escrow_balance NUMERIC(12,2) DEFAULT 0` to `migrate.js`
- Create `exports.lockEscrow` — deducts from sender wallet → sets `orders.escrow_balance`
- Create `exports.releaseEscrowPayment` — atomic transaction: checks delivery status, deducts escrow, credits courier wallet, logs to `wallet_ledger`
- Add routes `POST /api/orders/:id/escrow/lock` and `POST /api/orders/:id/escrow/release`

---

### FEATURE 4 — Real Camera Scanner (CourierScannerScreen)

**Gap:** `courier_scanner_screen.dart` in `presentation/screens/` is a 33-line stub with a fake "Simulate Scan" button. `mobile_scanner: ^5.0.0` is already in pubspec. The wiring in `delivery_detail_screen.dart` is correct — it just needs the stub replaced.

**Plan:**
- Replace the stub with a proper `MobileScanner` widget implementation with scanning overlay, torch toggle, and QR barcode detection
- On a valid barcode detect, call `onScan(barcode.rawValue)` once and close

---

### FEATURE 6 — Profile Image Cache Persistence

**Gap:** `profileImageUrl` is fetched from the server via `profileNotifierProvider` but is **not cached to SharedPreferences**. On a fresh app restart (before the profile API responds), the avatar shows a blank placeholder. The user JSON in SharedPrefs already stores `profileImageUrl` from login — but it's stale if they upload a new picture. The `profile_provider.dart` updates state in memory but doesn't write back to SharedPrefs.

**Plan:**
- In `ProfileNotifier.uploadProfileImage()`, after updating the in-memory state, also call `SharedPreferences.setString('user_json', ...)` with the updated URL
- In `currentUserProvider` (which reads from SharedPrefs), the cached URL will now survive restarts immediately

---

## Proposed Changes

### Backend — `backend-api/`

#### [MODIFY] [migrate.js](file:///c:/Users/john/dakika0/backend-api/migrate.js)
- Add `escrow_balance NUMERIC(12,2) DEFAULT 0 CHECK (escrow_balance >= 0)` column to orders
- Ensure wallets table creation is idempotent (already present, verify)

#### [MODIFY] [controllers/orderController.js](file:///c:/Users/john/dakika0/backend-api/controllers/orderController.js)
- Add `notifyOrderCreator(orderId, newStatus)` helper (FCM push to creator, non-fatal)
- Inject into `acceptOrder`, `pickupOrder`, `completeOrder`
- Add `exports.lockEscrow` and `exports.releaseEscrowPayment` with full DB transaction atomicity

#### [MODIFY] [controllers/authController.js](file:///c:/Users/john/dakika0/backend-api/controllers/authController.js)
- Change JWT `expiresIn` from `'7d'` → `'30d'`

#### [MODIFY] [routes/orderRoutes.js](file:///c:/Users/john/dakika0/backend-api/routes/orderRoutes.js)
- Add `POST /api/orders/:id/escrow/lock` and `POST /api/orders/:id/escrow/release`

---

### Flutter — `lib/`

#### [MODIFY] [pubspec.yaml](file:///c:/Users/john/dakika0/pubspec.yaml)
- Add `geocoding: ^3.0.0`

#### [MODIFY] [lib/core/services/location_service.dart](file:///c:/Users/john/dakika0/lib/core/services/location_service.dart)
- Add `getAddressFromCoordinates(double lat, double lng)` method using `placemarkFromCoordinates`

#### [MODIFY] [lib/features/delivery/presentation/screens/request_delivery_screen.dart](file:///c:/Users/john/dakika0/lib/features/delivery/presentation/screens/request_delivery_screen.dart)
- Call `locationService.getAddressFromCoordinates()` and populate pickup field with real address

#### [MODIFY] [lib/features/delivery/presentation/screens/courier_scanner_screen.dart](file:///c:/Users/john/dakika0/lib/features/delivery/presentation/screens/courier_scanner_screen.dart)
- Replace placeholder stub with full `MobileScanner` implementation

#### [MODIFY] [lib/features/profile/providers/profile_provider.dart](file:///c:/Users/john/dakika0/lib/features/profile/providers/profile_provider.dart)
- After uploading a profile image, write the new URL back to the SharedPrefs `user_json` cache

---

## Verification Plan

### Backend
- Run `node migrate.js` — verify `escrow_balance` column added without error
- Test `POST /api/orders/:id/escrow/lock` with insufficient balance → expect 402
- Test `POST /api/orders/:id/escrow/release` on a delivered order → courier wallet incremented, ledger row created
- Check Render logs for `[Push]` entries after an order status change

### Flutter
- Hot restart after uploading profile image — avatar should persist without a network fetch
- On the request delivery screen with GPS permission granted, the pickup field should show a real address (e.g. "Kinondoni, Dar es Salaam"), not "Current GPS Location"
- Open `CourierScannerScreen` — real camera viewfinder should appear with scanning overlay
