import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/services/payment/getnet_usb_payment_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cl.gournet.kiosk/getnet');

  test('envía monto y correlativo y conserva auditoría Getnet', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return <String, dynamic>{
            'approved': true,
            'paymentReference': '42',
            'authorizationCode': 'ABC123',
            'operationId': '42',
            'responseCode': 0,
            'message': 'Aprobado',
            'commerceCode': '550062700310',
            'terminalId': 'IM30-01',
            'ticket': '17',
            'amount': 2500,
            'cardBrand': 'VI',
            'cardType': 'DB',
            'last4Digits': '6677',
            'transactionDate': '2026-09-11 18:05:09',
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final result = await const GetnetUsbPaymentGateway().pay(
      amount: 2500,
      transactionId: '12345678-1234-4234-9234-123456789abc',
      ticketNumber: 17,
    );

    expect(captured?.method, 'sale');
    final arguments = captured?.arguments as Map<Object?, Object?>;
    expect(arguments['amount'], 2500);
    expect(arguments['ticketNumber'], '17');
    expect(result.approved, isTrue);
    expect(result.authorizationCode, '42');
    expect(result.getnetTransaction?.authorizationCode, 'ABC123');
    expect(result.getnetTransaction?.last4Digits, '6677');
  });

  test('envía la cancelación controlada al canal nativo', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return <String, dynamic>{
            'accepted': true,
            'message': 'Solicitud enviada',
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final result = await const GetnetUsbPaymentGateway().cancelActivePayment();

    expect(captured?.method, 'cancelSale');
    expect(result.accepted, isTrue);
  });
}
