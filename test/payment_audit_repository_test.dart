import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/data/local/payment_audit_repository.dart';
import 'package:gournet_kiosk/domain/models/order.dart';
import 'package:gournet_kiosk/services/payment/payment_gateway.dart';

void main() {
  late Directory directory;
  late PaymentAuditRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('payment-audit-test-');
    repository = PaymentAuditRepository(
      storageDirectory: () async => directory,
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('bloquea un segundo cobro mientras el primero está activo', () async {
    final first = await repository.begin(
      transactionId: 'payment-1',
      orderNumber: 7,
      amount: 4500,
    );
    final duplicate = await repository.begin(
      transactionId: 'payment-1',
      orderNumber: 7,
      amount: 4500,
    );

    expect(first.allowed, isTrue);
    expect(duplicate.allowed, isFalse);
    expect(duplicate.message, contains('pendiente de conciliación'));
  });

  test('guarda respuesta aprobada y bloquea volver a cobrarla', () async {
    final first = await repository.begin(
      transactionId: 'payment-2',
      orderNumber: 8,
      amount: 2500,
    );
    await repository.complete(
      first.entryId!,
      const PaymentResult(
        approved: true,
        authorizationCode: '123456',
        getnetTransaction: GetnetTransactionData(
          responseCode: 0,
          responseMessage: 'Aprobado',
          commerceCode: 'COM-1',
          terminalId: 'POS-1',
          ticket: '8',
          authorizationCode: '123456',
          operationId: '42',
          amount: 2500,
          cardBrand: 'VI',
          cardType: 'DB',
          last4Digits: '6677',
          transactionDate: '2026-09-11T19:00:00',
        ),
      ),
    );

    final duplicate = await repository.begin(
      transactionId: 'different-id',
      orderNumber: 8,
      amount: 2500,
    );
    final saved = await repository.readAll();

    expect(duplicate.allowed, isFalse);
    expect(duplicate.message, contains('ya tiene un pago aprobado'));
    expect(saved.single['status'], PaymentAuditStatus.approved.name);
    expect(saved.single['paymentReference'], '123456');
    expect((saved.single['getnet'] as Map)['operationId'], '42');
    expect((saved.single['getnet'] as Map)['last4Digits'], '6677');
  });

  test('permite reintentar sólo después de un rechazo confirmado', () async {
    final first = await repository.begin(
      transactionId: 'payment-3',
      orderNumber: 9,
      amount: 3100,
    );
    await repository.complete(
      first.entryId!,
      const PaymentResult(
        approved: false,
        authorizationCode: '',
        message: 'Rechazado',
      ),
    );

    final retry = await repository.begin(
      transactionId: 'payment-3',
      orderNumber: 9,
      amount: 3100,
    );

    expect(retry.allowed, isTrue);
    expect(await repository.readAll(), hasLength(2));
  });

  test('un resultado incierto queda bloqueado para conciliación', () async {
    final first = await repository.begin(
      transactionId: 'payment-4',
      orderNumber: 10,
      amount: 6000,
    );
    await repository.complete(
      first.entryId!,
      const PaymentResult(
        approved: false,
        authorizationCode: '',
        message: 'Tiempo de espera agotado',
        outcomeCertain: false,
      ),
    );

    final retry = await repository.begin(
      transactionId: 'different-payment',
      orderNumber: 11,
      amount: 2000,
    );

    expect(retry.allowed, isFalse);
    expect((await repository.readAll()).single['status'], 'uncertain');

    await repository.resolveManually(first.entryId!, paymentConfirmed: false);
    final afterReconciliation = await repository.begin(
      transactionId: 'different-payment',
      orderNumber: 11,
      amount: 2000,
    );
    expect(afterReconciliation.allowed, isTrue);
  });
}
