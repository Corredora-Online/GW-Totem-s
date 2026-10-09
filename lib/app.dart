import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/adaptive_kiosk_viewport.dart';
import 'core/widgets/idle_guard.dart';
import 'data/remote/gournet_branches_repository.dart';
import 'domain/models/branch.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'services/kiosk/kiosk_service.dart';
import 'state/app_providers.dart';
import 'state/device_config_controller.dart';

class GournetKioskApp extends ConsumerStatefulWidget {
  const GournetKioskApp({super.key});

  @override
  ConsumerState<GournetKioskApp> createState() => _GournetKioskAppState();
}

class _GournetKioskAppState extends ConsumerState<GournetKioskApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncKioskMode());
      unawaited(_migrateBranchTus());
    });
  }

  Future<void> _syncKioskMode() =>
      KioskService.setEnabled(ref.read(deviceConfigProvider).isActivated);

  Future<void> _migrateBranchTus() async {
    final config = ref.read(deviceConfigProvider);
    final endpoint = Uri.tryParse(config.branchesEndpoint.trim());
    if (endpoint == null || config.apiKey.trim().isEmpty) return;

    final repository = GournetBranchesRepository();
    try {
      final branches = await repository.load(
        apiKey: config.apiKey.trim(),
        endpoint: endpoint,
      );
      if (!mounted) return;

      Branch? selected;
      for (final branch in branches) {
        if (branch.id == config.branchId) {
          selected = branch;
          break;
        }
      }
      if (selected == null) {
        for (final branch in branches) {
          if (branch.code == config.branchCode) {
            selected = branch;
            break;
          }
        }
      }

      if (selected == null) return;

      // Repara configuraciones guardadas por versiones que confundían el _ID
      // interno (24) con el TUS alfanumérico (5QQTw5u1K8ed).
      final resolvedTus = selected.code.trim();
      if (selected.id == config.branchId &&
          (resolvedTus.isEmpty || resolvedTus == config.branchCode) &&
          selected.name == config.branchName) {
        return;
      }
      await ref
          .read(deviceConfigProvider.notifier)
          .replace(
            config.copyWith(
              branchId: selected.id,
              branchCode: resolvedTus.isEmpty ? config.branchCode : resolvedTus,
              branchName: selected.name,
            ),
          );
    } catch (_) {
      // La configuración existente se conserva si la API no está disponible.
    } finally {
      repository.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      deviceConfigProvider.select((config) => config.isActivated),
      (previous, activated) => unawaited(KioskService.setEnabled(activated)),
    );
    final config = ref.watch(deviceConfigProvider);
    final primary = _parseColor(config.primaryColor) ?? AppColors.primary;
    if (!config.isActivated) {
      return MaterialApp(
        title: 'Activar Gour-net Kiosk',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.withPrimary(primary),
        home: const OnboardingScreen(),
        builder: (context, child) => AdaptiveKioskViewport(
          enabled: Platform.isWindows,
          child: child ?? const SizedBox(),
        ),
      );
    }

    // Mantiene la sincronización activa incluso durante el video de espera.
    ref.watch(catalogProvider);
    ref.watch(orderSyncProvider);
    return MaterialApp.router(
      title: 'Gour-net Kiosk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.withPrimary(primary),
      routerConfig: appRouter,
      builder: (context, child) => AdaptiveKioskViewport(
        enabled: Platform.isWindows,
        child: IdleGuard(child: child ?? const SizedBox()),
      ),
    );
  }

  Color? _parseColor(String value) {
    final normalized = value.trim().replaceFirst('#', '');
    if (normalized.length != 6) return null;
    final parsed = int.tryParse(normalized, radix: 16);
    return parsed == null ? null : Color(0xFF000000 | parsed);
  }
}
