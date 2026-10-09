import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Gives high-resolution kiosk monitors a usable touch-sized viewport.
/// Android already receives density-adjusted logical pixels from the OS.
class AdaptiveKioskViewport extends StatelessWidget {
  const AdaptiveKioskViewport({
    super.key,
    required this.child,
    required this.enabled,
  });

  final Widget child;
  final bool enabled;

  static double scaleFor(Size size) {
    final portrait = size.height >= size.width;
    final target = portrait ? const Size(720, 1280) : const Size(1280, 720);
    return math
        .min(size.width / target.width, size.height / target.height)
        .clamp(1.0, 1.6)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return child;
        }
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final scale = scaleFor(size);
        if (scale == 1) return child;
        final viewport = Size(size.width / scale, size.height / scale);
        return FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: viewport),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
