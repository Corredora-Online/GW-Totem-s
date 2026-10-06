import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cart/cart_controller.dart';
import '../checkout/checkout_controller.dart';
import 'session_controller.dart';

final sessionResetProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(cartProvider.notifier).clear();
    ref.read(sessionProvider.notifier).reset();
    ref.read(checkoutProvider.notifier).reset();
  };
});
