import 'package:flutter/services.dart';

import '../../domain/models/order.dart';
import 'payment_gateway.dart';

class GetnetUsbPaymentGateway implements PaymentGateway {
  const GetnetUsbPaymentGateway();

  static const channel = MethodChannel('cl.gournet.kiosk/getnet');

  @override
  Future<PaymentResult> pay({
    required int amount,
    required String transactionId,
    required int ticketNumber,
  }) async {
    try {
      final response = await channel.invokeMapMethod<String, dynamic>('sale', {
        'amount': amount,
        'ticketNumber': ticketNumber.toString(),
        'transactionId': transactionId,
      });
      if (response == null) {
        return const PaymentResult(
          approved: false,
          authorizationCode: '',
          message: 'El terminal Getnet no entregó una respuesta.',
        );
      }
      return PaymentResult(
        approved: response['approved'] == true,
        authorizationCode:
            response['paymentReference']?.toString().trim() ?? '',
        message: response['message']?.toString(),
        getnetTransaction: _transactionData(response),
        outcomeCertain: response['outcomeCertain'] != false,
        cancelled: response['cancelled'] == true,
      );
    } on MissingPluginException {
      return const PaymentResult(
        approved: false,
        authorizationCode: '',
        message: 'La integración Getnet USB no está disponible.',
      );
    } on PlatformException catch (error) {
      return PaymentResult(
        approved: false,
        authorizationCode: '',
        message: error.message ?? 'Falló la comunicación con Getnet.',
        outcomeCertain: false,
      );
    }
  }

  @override
  Future<PaymentCancellationResult> cancelActivePayment() async {
    try {
      final response = await channel.invokeMapMethod<String, dynamic>(
        'cancelSale',
      );
      return PaymentCancellationResult(
        accepted: response?['accepted'] == true,
        message: response?['message']?.toString(),
      );
    } on MissingPluginException {
      return const PaymentCancellationResult(
        accepted: false,
        message: 'La integración Getnet USB no está disponible.',
      );
    } on PlatformException catch (error) {
      return PaymentCancellationResult(
        accepted: false,
        message: error.message ?? 'No se pudo solicitar la cancelación.',
      );
    }
  }

  GetnetTransactionData _transactionData(Map<String, dynamic> response) {
    int integer(String key) {
      final value = response[key];
      return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    }

    String text(String key) => response[key]?.toString().trim() ?? '';
    return GetnetTransactionData(
      responseCode: integer('responseCode'),
      responseMessage: text('message'),
      commerceCode: text('commerceCode'),
      terminalId: text('terminalId'),
      ticket: text('ticket'),
      authorizationCode: text('authorizationCode'),
      operationId: text('operationId'),
      amount: integer('amount'),
      cardBrand: text('cardBrand'),
      cardType: text('cardType'),
      last4Digits: text('last4Digits'),
      transactionDate: text('transactionDate'),
    );
  }
}
