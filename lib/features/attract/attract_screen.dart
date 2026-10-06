import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/security/settings_access.dart';
import '../../core/widgets/brand_mark.dart';
import '../../features/settings/admin_pin_dialog.dart';
import '../../state/device_config_controller.dart';
import '../../state/session/session_reset.dart';
import '../../state/update_controller.dart';

class AttractScreen extends ConsumerStatefulWidget {
  const AttractScreen({super.key});

  @override
  ConsumerState<AttractScreen> createState() => _AttractScreenState();
}

class _AttractScreenState extends ConsumerState<AttractScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final VideoPlayerController _videoController;
  late final AnimationController _pulseController;
  bool _videoReady = false;
  bool _videoFailed = false;
  int _adminTapCount = 0;
  DateTime? _firstAdminTapAt;
  Timer? _updateTimer;

  bool get _idleForUpdate => mounted && ModalRoute.of(context)?.isCurrent == true;

  void _checkUpdate() {
    if (!_idleForUpdate) return;
    unawaited(ref.read(updateProvider.notifier).check(screenIdle: () => _idleForUpdate));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _videoController = VideoPlayerController.asset('assets/videos/standby.mp4');
    unawaited(_prepareVideo());
    _updateTimer = Timer.periodic(const Duration(seconds: 45), (_) => _checkUpdate());
  }

  Future<void> _prepareVideo() async {
    try {
      await _videoController.initialize();
      await _videoController.setLooping(true);
      await _videoController.setVolume(0);
      await _videoController.play();
      if (mounted) setState(() => _videoReady = true);
    } catch (_) {
      if (mounted) setState(() => _videoFailed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_videoReady) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_videoController.play());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_videoController.pause());
    }
  }

  void _start() {
    if (ref.read(updateProvider).installing) return;
    ref.read(sessionResetProvider)();
    context.go('/order-type');
  }

  void _registerAdminTap() {
    if (ref.read(updateProvider).installing) return;
    final now = DateTime.now();
    if (_firstAdminTapAt == null ||
        now.difference(_firstAdminTapAt!) > const Duration(seconds: 3)) {
      _firstAdminTapAt = now;
      _adminTapCount = 0;
    }
    _adminTapCount++;
    if (_adminTapCount < 5) return;
    _adminTapCount = 0;
    _firstAdminTapAt = null;
    unawaited(_openSettings());
  }

  Future<void> _openSettings() async {
    final config = ref.read(deviceConfigProvider);
    final allowed = await showAdminPinDialog(
      context,
      expectedHash: config.adminPinHash,
    );
    if (!mounted || !allowed) return;
    await context.push('/settings', extra: settingsAccessGrant);
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(updateProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Semantics(
        button: true,
        label: 'Toca la pantalla para comenzar tu pedido',
        child: GestureDetector(
          key: const Key('standby-touch-target'),
          behavior: HitTestBehavior.opaque,
          onTap: _start,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _StandbyMedia(
                controller: _videoController,
                ready: _videoReady,
                failed: _videoFailed,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, .48, 1],
                    colors: [
                      Colors.black38,
                      Colors.transparent,
                      Colors.black87,
                    ],
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: GestureDetector(
                      key: const Key('admin-gesture-target'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _registerAdminTap,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: BrandMark(light: true),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 54),
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) => Opacity(
                        opacity: .88 + _pulseController.value * .12,
                        child: Transform.scale(
                          scale: 1 + _pulseController.value * .025,
                          child: child,
                        ),
                      ),
                      child: const _TouchPrompt(),
                    ),
                  ),
                ),
              ),
              if (update.installing)
                Positioned.fill(child: ColoredBox(
                  color: Colors.black87,
                  child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text(update.message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24)),
                  ])),
                )),
            ],
          ),
        ),
      ),
    );
  }
}

class _StandbyMedia extends StatelessWidget {
  const _StandbyMedia({
    required this.controller,
    required this.ready,
    required this.failed,
  });

  final VideoPlayerController controller;
  final bool ready;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    if (ready) {
      final size = controller.value.size;
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(controller),
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/products/cheeseburger.png',
          fit: BoxFit.cover,
        ),
        if (!failed)
          const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
      ],
    );
  }
}

class _TouchPrompt extends StatelessWidget {
  const _TouchPrompt();

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 600),
    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .95),
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(color: Colors.black38, blurRadius: 30, offset: Offset(0, 12)),
      ],
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.primary,
          child: Icon(Icons.touch_app_rounded, color: Colors.white, size: 31),
        ),
        SizedBox(width: 18),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOCA LA PANTALLA',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .4,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'para comenzar tu pedido',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
