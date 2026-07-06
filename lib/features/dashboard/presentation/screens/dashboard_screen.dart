import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/demo_mode.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/websocket_service.dart';
import '../../../../core/widgets/notification_overlay.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../orders/providers/order_provider.dart';
import '../../../profile/providers/profile_provider.dart';
import 'home_screen.dart';
import 'courier_map_feed_screen.dart';
import '../../../delivery/presentation/screens/active_deliveries_screen.dart';
import '../../../delivery/presentation/screens/delivery_detail_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';

enum DashboardTab { home, mapFeed, delivery, profile }

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DashboardTab _currentTab = DashboardTab.home;
  StreamSubscription? _wsEventSubscription;

  @override
  void initState() {
    super.initState();
    _initLocationPermission();
    _initWebSocket();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(myActiveOrdersProvider);
      ref.invalidate(orderStatsProvider);
      ref.invalidate(profileNotifierProvider);
    });
  }

  @override
  void dispose() {
    _wsEventSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initWebSocket() async {
    // ── DEMO MODE: skip WebSocket ──────────────────────────────────────────
    if (kDemoMode) return;
    // ──────────────────────────────────────────────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null && mounted) {
      final wsService = ref.read(webSocketServiceProvider);
      await wsService.connect(token);

      // Listen for notifications/broadcasts
      _wsEventSubscription = wsService.eventStream.listen((event) {
        if (event['type'] == 'order_broadcast' && mounted) {
          final order = event['order'];
          final itemType = order['itemType'] ?? 'Delivery';
          final pickup = order['pickupAddress'] ?? '';
          final price = (order['estimatedPrice'] as num?)?.toDouble() ?? 0.0;
          final orderId = order['id'] as String;

          NotificationOverlay.show(
            context,
            title: "New Delivery Order Nearby!",
            message:
                "$itemType \u2022 TZS ${price.toStringAsFixed(0)}\nPickup: $pickup",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DeliveryDetailScreen(orderId: orderId),
                ),
              );
            },
          );
        }
      });
    }
  }

  Future<void> _initLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
  }

  void _onTabTapped(DashboardTab tab) {
    setState(() => _currentTab = tab);
    // Refresh data when switching tabs so lists are always fresh
    ref.invalidate(myActiveOrdersProvider);
    ref.invalidate(orderStatsProvider);
    ref.invalidate(profileNotifierProvider);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserAsync = ref.watch(currentUserProvider);
    final user = currentUserAsync.valueOrNull;
    final isVerified = user?.isFullyVerified ?? false;

    // Define the tabs available in the current user context
    final activeTabs = [
      DashboardTab.home,
      if (isVerified) DashboardTab.mapFeed,
      DashboardTab.delivery,
      DashboardTab.profile,
    ];

    // Fallback to home if the current tab is no longer available (e.g. unverified)
    if (!activeTabs.contains(_currentTab)) {
      _currentTab = DashboardTab.home;
    }

    final currentIndex = activeTabs.indexOf(_currentTab);

    // Build list of screen widgets corresponding to active tabs
    final List<Widget> screens = activeTabs.map((tab) {
      switch (tab) {
        case DashboardTab.home:
          return const HomeScreen();
        case DashboardTab.mapFeed:
          return const CourierMapFeedScreen();
        case DashboardTab.delivery:
          return const ActiveDeliveriesScreen();
        case DashboardTab.profile:
          return const ProfileScreen();
      }
    }).toList();

    return Scaffold(
      body: IndexedStack(index: currentIndex, children: screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (index) => _onTabTapped(activeTabs[index]),
          backgroundColor: isDark ? AppColors.navy : AppColors.white,
          selectedItemColor: isDark ? AppColors.gold : AppColors.navy,
          unselectedItemColor: Colors.grey,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          items: activeTabs.map((tab) {
            switch (tab) {
              case DashboardTab.home:
                return const BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Home',
                );
              case DashboardTab.mapFeed:
                return const BottomNavigationBarItem(
                  icon: Icon(Icons.map_outlined),
                  activeIcon: Icon(Icons.map),
                  label: 'Map Feed',
                );
              case DashboardTab.delivery:
                return BottomNavigationBarItem(
                  icon: const Icon(Icons.delivery_dining_outlined),
                  activeIcon: const Icon(Icons.delivery_dining),
                  label: context.tr('delivery'),
                );
              case DashboardTab.profile:
                return BottomNavigationBarItem(
                  icon: const Icon(Icons.person_outline),
                  activeIcon: const Icon(Icons.person),
                  label: context.tr('profile'),
                );
            }
          }).toList(),
        ),
      ),
    );
  }
}
