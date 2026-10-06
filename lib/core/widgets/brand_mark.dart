import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/device_config_controller.dart';
import '../theme/app_colors.dart';

class BrandMark extends ConsumerWidget {
  const BrandMark({super.key, this.light = false, this.showRestaurant = true});

  final bool light;
  final bool showRestaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(deviceConfigProvider);
    final foreground = light ? Colors.white : AppColors.textPrimary;
    return Semantics(
      label: 'Gour-net ${config.restaurantName}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: light ? Colors.white : AppColors.primary,
              borderRadius: BorderRadius.circular(18),
            ),
            child: _logo(config.logo),
          ),
          if (showRestaurant) ...[
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  config.restaurantName,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Gour-net Kiosk',
                  style: TextStyle(
                    color: foreground.withValues(alpha: .7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _logo(String source) {
    final fallback = Text(
      'G',
      style: TextStyle(
        color: light ? AppColors.primary : Colors.white,
        fontWeight: FontWeight.w900,
        fontSize: 28,
      ),
    );
    if (source.trim().isEmpty) return fallback;
    final uri = Uri.tryParse(source.trim());
    Widget image;
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      image = Image.network(
        source.trim(),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    } else if (source.startsWith('assets/')) {
      image = Image.asset(
        source.trim(),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    } else {
      image = Image.file(
        File(source.trim()),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }
    return Padding(padding: const EdgeInsets.all(6), child: image);
  }
}
