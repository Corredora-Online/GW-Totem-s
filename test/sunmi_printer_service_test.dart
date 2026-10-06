import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/domain/models/order.dart';
import 'package:gournet_kiosk/services/printer/sunmi_printer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cl.gournet.kiosk/printer');

  test('envía el mismo correlativo a la impresión nativa', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return <String, dynamic>{'success': true};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final order = Order(
      uuid: '12345678-1234-4234-9234-123456789abc',
      number: 0,
      type: OrderType.eatIn,
      items: const [],
      paymentStatus: PaymentStatus.approved,
      dteStatus: DteStatus.pending,
      syncStatus: SyncStatus.pending,
      createdAt: DateTime(2026, 9, 9, 12),
      paymentReference: '12345678',
      getnetTransaction: const GetnetTransactionData(
        responseCode: 0,
        responseMessage: 'Aprobado',
        commerceCode: '550062700310',
        terminalId: 'IM30-01',
        ticket: '0',
        authorizationCode: 'ABC123',
        operationId: '42',
        amount: 2500,
        cardBrand: 'VI',
        cardType: 'DB',
        last4Digits: '6677',
        transactionDate: '2026-09-11 18:05:09',
      ),
    );

    final result = await const SunmiPrinterService(
      windowsPrinterName: 'POS-80',
    ).print(order);

    expect(result.success, isTrue);
    expect(captured?.method, 'printReceipt');
    final arguments = captured?.arguments as Map<Object?, Object?>;
    expect(arguments['orderNumber'], '0');
    expect(arguments['printerName'], 'POS-80');
    expect(arguments['body'].toString(), contains('COMPROBANTE DE PEDIDO'));
    expect(arguments['body'].toString(), contains('DOCUMENTO NO TRIBUTARIO'));
    expect(arguments['body'].toString(), isNot(contains('NO ES BOLETA')));
    expect(arguments['body'].toString(), contains('Operacion'));
    expect(arguments['body'].toString(), contains('42'));
    expect(arguments['body'].toString(), contains('**** 6677'));
    expect(arguments['body'].toString(), isNot(contains('#104')));
    expect(
      arguments['footer'].toString(),
      contains('NO VALIDO COMO DOCUMENTO TRIBUTARIO'),
    );
  });
}
