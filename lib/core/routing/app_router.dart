import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/cart_item.dart';
import '../../domain/models/order.dart';
import '../security/settings_access.dart';
import '../../features/attract/attract_screen.dart';
import '../../features/cart/cart_screen.dart';
import '../../features/catalog/catalog_screen.dart';
import '../../features/checkout/checkout_screen.dart';
import '../../features/order_type/order_type_screen.dart';
import '../../features/processing/processing_screen.dart';
import '../../features/product_detail/product_detail_screen.dart';
import '../../features/success/success_screen.dart';
import '../../features/settings/settings_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => _page(state, const AttractScreen()),
    ),
    GoRoute(
      path: '/order-type',
      pageBuilder: (context, state) => _page(state, const OrderTypeScreen()),
    ),
    GoRoute(
      path: '/catalog',
      pageBuilder: (context, state) => _page(state, const CatalogScreen()),
    ),
    GoRoute(
      path: '/product/:id',
      pageBuilder: (context, state) => _page(
        state,
        ProductDetailScreen(
          productId: state.pathParameters['id']!,
          editingItem: state.extra is CartItem
              ? state.extra! as CartItem
              : null,
        ),
      ),
    ),
    GoRoute(
      path: '/cart',
      pageBuilder: (context, state) => _page(state, const CartScreen()),
    ),
    GoRoute(
      path: '/checkout',
      pageBuilder: (context, state) => _page(state, const CheckoutScreen()),
    ),
    GoRoute(
      path: '/processing',
      pageBuilder: (context, state) => _page(
        state,
        state.extra is Order
            ? ProcessingScreen(order: state.extra! as Order)
            : const _InvalidFlowScreen(),
      ),
    ),
    GoRoute(
      path: '/success',
      pageBuilder: (context, state) => _page(
        state,
        state.extra is CompletionData
            ? SuccessScreen(data: state.extra! as CompletionData)
            : const _InvalidFlowScreen(),
      ),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) => _page(
        state,
        identical(state.extra, settingsAccessGrant)
            ? const SettingsScreen()
            : const _InvalidFlowScreen(),
      ),
    ),
  ],
  errorBuilder: (context, state) => const _InvalidFlowScreen(),
);

CustomTransitionPage<void> _page(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
    );

class _InvalidFlowScreen extends StatelessWidget {
  const _InvalidFlowScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.route_outlined, size: 60),
          const SizedBox(height: 16),
          const Text('Esta sesión ya no está disponible.'),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => context.go('/'),
            child: const Text('VOLVER AL INICIO'),
          ),
        ],
      ),
    ),
  );
}
