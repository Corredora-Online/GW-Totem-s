import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/device_config_controller.dart';
import '../../state/session/session_reset.dart';
import '../routing/app_router.dart';

class IdleGuard extends ConsumerStatefulWidget {
  const IdleGuard({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<IdleGuard> createState() => _IdleGuardState();
}

class _IdleGuardState extends ConsumerState<IdleGuard> {
  Timer? _idleTimer;
  Timer? _cancelTimer;
  bool _dialogVisible = false;

  bool get _isGuardedRoute {
    final path = appRouter.routerDelegate.currentConfiguration.uri.path;
    return const {'/catalog', '/cart'}.contains(path) ||
        path.startsWith('/product/');
  }

  @override
  void initState() {
    super.initState();
    appRouter.routerDelegate.addListener(_handleRouteChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleRouteChanged());
  }

  void _handleRouteChanged() {
    if (!mounted) return;
    _idleTimer?.cancel();
    if (!_isGuardedRoute) {
      _cancelTimer?.cancel();
      return;
    }
    _scheduleIdleTimer();
  }

  void _registerActivity([PointerEvent? event]) {
    if (_dialogVisible || !_isGuardedRoute) return;
    _scheduleIdleTimer();
  }

  void _scheduleIdleTimer() {
    _idleTimer?.cancel();
    final timeout = ref.read(deviceConfigProvider).idleTimeoutSeconds;
    _idleTimer = Timer(Duration(seconds: timeout), _showIdleDialog);
  }

  Future<void> _showIdleDialog() async {
    if (!mounted || !_isGuardedRoute || _dialogVisible) return;
    final navigatorContext = rootNavigatorKey.currentContext;
    if (navigatorContext == null) return;
    _dialogVisible = true;
    final remainingSeconds = ValueNotifier<int>(15);
    _cancelTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final next = remainingSeconds.value - 1;
      remainingSeconds.value = next;
      if (next <= 0) {
        timer.cancel();
        _cancelSession();
      }
    });
    await showDialog<void>(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.touch_app_rounded, size: 56),
        title: const Text('¿Sigues ahí?', textAlign: TextAlign.center),
        content: ValueListenableBuilder<int>(
          valueListenable: remainingSeconds,
          builder: (context, seconds, child) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Continúa tu pedido o lo borraremos para el próximo cliente.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE6F2),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$seconds',
                  key: const Key('idle-countdown'),
                  style: const TextStyle(
                    color: Color(0xFFE5187E),
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('segundos', textAlign: TextAlign.center),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            key: const Key('cancel-session-button'),
            onPressed: _cancelSession,
            child: const Text('BORRAR PEDIDO'),
          ),
          ElevatedButton(
            key: const Key('continue-session-button'),
            onPressed: () {
              _cancelTimer?.cancel();
              Navigator.of(dialogContext).pop();
            },
            child: const Text('CONTINUAR PEDIDO'),
          ),
        ],
      ),
    );
    _cancelTimer?.cancel();
    remainingSeconds.dispose();
    _dialogVisible = false;
    _registerActivity();
  }

  void _cancelSession() {
    if (!mounted) return;
    final navigator = rootNavigatorKey.currentState;
    if (_dialogVisible && navigator != null && navigator.canPop()) {
      navigator.pop();
    }
    ref.read(sessionResetProvider)();
    appRouter.go('/');
  }

  @override
  void dispose() {
    appRouter.routerDelegate.removeListener(_handleRouteChanged);
    _idleTimer?.cancel();
    _cancelTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _registerActivity,
      child: widget.child,
    );
  }
}
