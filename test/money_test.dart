import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/core/formatting/money.dart';

void main() {
  test('formatea pesos chilenos sin decimales', () {
    expect(formatClp(8990), r'$8.990');
    expect(formatClp(2500), r'$2.500');
    expect(formatClp(0), r'$0');
  });
}
