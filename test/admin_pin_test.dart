import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/core/security/admin_pin.dart';

void main() {
  test('el PIN administrativo exige seis dígitos y compara su hash', () {
    final hash = AdminPin.hash('258369');

    expect(AdminPin.isValid('258369', hash), isTrue);
    expect(AdminPin.isValid('258368', hash), isFalse);
    expect(AdminPin.isValid('25836', hash), isFalse);
  });
}
