import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class KioskPage extends StatelessWidget {
  const KioskPage({
    super.key,
    required this.child,
    this.maxWidth = 1400,
    this.padding = const EdgeInsets.all(32),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
