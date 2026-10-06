import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/services/payment/windows_getnet_payment_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cl.gournet.kiosk/getnet');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('firma la venta y conserva el resultado Getnet para conciliación', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return {
            'response': WindowsGetnetPaymentGateway.signedCommand({
              'FunctionCode': 100,
              'ResponseCode': 0,
              'ResponseMessage': 'Aprobado',
              'Amount': 2500,
              'Ticket': '17',
              'OperationId': 'OP-17',
              'AuthorizationCode': 'AUTH-17',
              'TerminalId': 'IM30',
              'Last4Digits': '6677',
            }),
            'delivered': true,
            'message': '',
          };
        });

    final result = await const WindowsGetnetPaymentGateway(port: 'COM5').pay(
      amount: 2500,
      transactionId: 'random-idempotency-key',
      ticketNumber: 17,
    );

    expect(captured?.method, 'sale');
    final arguments = captured!.arguments as Map<Object?, Object?>;
    expect(arguments['port'], 'COM5');
    final command = WindowsGetnetPaymentGateway.verifySignedResponse(
      arguments['payload']! as String,
    );
    expect(command['Command'], 100);
    expect(command['Amount'], 2500);
    expect(command['TicketNumber'], '17');
    expect(result.approved, isTrue);
    expect(result.authorizationCode, 'OP-17');
    expect(result.getnetTransaction?.last4Digits, '6677');
  });

  test('bloquea reintento ante monto aprobado inconsistente', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => {
          'response': WindowsGetnetPaymentGateway.signedCommand({
            'FunctionCode': 100,
            'ResponseCode': 0,
            'Amount': 9999,
            'Ticket': '17',
          }),
          'delivered': true,
          'message': '',
        });
    final result = await const WindowsGetnetPaymentGateway().pay(
      amount: 2500,
      transactionId: 'id',
      ticketNumber: 17,
    );
    expect(result.approved, isFalse);
    expect(result.outcomeCertain, isFalse);
  });

  test('distingue puerto sin abrir de venta enviada sin respuesta', () async {
    var delivered = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => {
          'response': '',
          'delivered': delivered,
          'message': 'Sin resultado',
        });
    const gateway = WindowsGetnetPaymentGateway();
    final beforeWrite = await gateway.pay(
      amount: 2500,
      transactionId: 'id',
      ticketNumber: 17,
    );
    expect(beforeWrite.outcomeCertain, isTrue);
    delivered = true;
    final afterWrite = await gateway.pay(
      amount: 2500,
      transactionId: 'id',
      ticketNumber: 17,
    );
    expect(afterWrite.outcomeCertain, isFalse);
  });

  test('rechaza una respuesta con firma inválida', () {
    final response = jsonEncode({
      'JsonSerialized': jsonEncode({'FunctionCode': 100}),
      'Sign': 'BAD',
    });
    expect(
      () => WindowsGetnetPaymentGateway.verifySignedResponse(response),
      throwsFormatException,
    );
  });

  test('envía cancelación firmada al mismo puerto activo', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return {'accepted': true, 'message': 'Solicitud enviada'};
        });
    final result = await const WindowsGetnetPaymentGateway()
        .cancelActivePayment();
    expect(result.accepted, isTrue);
    expect(captured?.method, 'cancelSale');
    final args = captured!.arguments as Map<Object?, Object?>;
    final command = WindowsGetnetPaymentGateway.verifySignedResponse(
      args['payload']! as String,
    );
    expect(command['Command'], 116);
  });
}
