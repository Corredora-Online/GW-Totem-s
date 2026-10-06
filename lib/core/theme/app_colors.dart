import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFFE5187E);
  static const secondary = Color(0xFF7130CF);
  static const background = Color(0xFFF7F6F8);
  static const surface = Colors.white;
  static const textPrimary = Color(0xFF20202A);
  static const textSecondary = Color(0xFF777783);
  static const border = Color(0xFFE7E5EA);
  static const success = Color(0xFF16865A);
  static const warning = Color(0xFFF1A129);
  static const error = Color(0xFFC9364B);
}

abstract final class AppRadii {
  static const small = 12.0;
  static const medium = 20.0;
  static const large = 32.0;
}

abstract final class AppSpacing {
  static const xs = 6.0;
  static const sm = 12.0;
  static const md = 20.0;
  static const lg = 32.0;
  static const xl = 48.0;
}
