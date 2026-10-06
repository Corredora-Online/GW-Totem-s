import 'dart:io';

import 'package:flutter/material.dart';

class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final String source;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final image = source.startsWith('http://') || source.startsWith('https://')
        ? Image.network(
            source,
            fit: fit,
            width: width,
            height: height,
            errorBuilder: _fallback,
          )
        : source.startsWith('assets/')
        ? Image.asset(
            source,
            fit: fit,
            width: width,
            height: height,
            errorBuilder: _fallback,
          )
        : Image.file(
            File(source),
            fit: fit,
            width: width,
            height: height,
            errorBuilder: _fallback,
          );
    return image;
  }

  Widget _fallback(BuildContext context, Object error, StackTrace? stack) =>
      Image.asset(
        'assets/images/products/cheeseburger.png',
        fit: fit,
        width: width,
        height: height,
      );
}
