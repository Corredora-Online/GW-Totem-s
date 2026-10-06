import 'dart:convert';

import 'package:crypto/crypto.dart';

abstract final class AdminPin {
  static const defaultPin = '258369';

  static String hash(String pin) =>
      sha256.convert(utf8.encode('gournet-kiosk-admin:$pin')).toString();

  static bool isValid(String pin, String expectedHash) =>
      pin.length == 6 && hash(pin) == expectedHash;
}
