import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../../domain/models/order.dart';
import 'payment_gateway.dart';

/// Protocolo POS Integrado Getnet sobre el puerto COM del IM30 en Windows.
/// El runner nativo sólo transporta bytes; firma, verificación y mapeo viven
/// aquí para mantener idéntica semántica de auditoría entre plataformas.
class WindowsGetnetPaymentGateway implements PaymentGateway {
  const WindowsGetnetPaymentGateway({this.port = ''});

  final String port;
  static const channel = MethodChannel('cl.gournet.kiosk/getnet');

  @override
  Future<PaymentResult> pay({
    required int amount,
    required String transactionId,
    required int ticketNumber,
  }) async {
    final ticket = ticketNumber.toString();
    final payload = signedCommand({
      'Command': 100,
      'Amount': amount,
      'TicketNumber': ticket,
      'PrintOnPos': false,
      'SaleType': 0,
      'SendMessage': false,
      'EmployeeId': 1,
      'DateTime': DateTime.now().toIso8601String(),
    });
    try {
      final transport = await channel.invokeMapMethod<String, dynamic>(
        'sale',
        {'payload': payload, 'port': port},
      );
      if (transport == null) return _uncertain('El POS no entregó respuesta.');
      final raw = transport['response']?.toString() ?? '';
      if (raw.isEmpty) {
        return PaymentResult(
          approved: false,
          authorizationCode: '',
          message: transport['message']?.toString() ??
              'No se pudo comunicar con el terminal.',
          outcomeCertain: transport['delivered'] == false,
        );
      }

      final response = verifySignedResponse(raw);
      final functionCode = _integer(response, 'FunctionCode');
      if (functionCode != 100) {
        return _uncertain('El POS entregó una respuesta inesperada.');
      }
      final code = _integer(response, 'ResponseCode', fallback: -1);
      final returnedTicket = _text(response, 'Ticket', 'TicketNumber');
      final returnedAmount = _integer(response, 'Amount');
      if (code == 0 &&
          ((returnedTicket.isNotEmpty && returnedTicket != ticket) ||
              (returnedAmount > 0 && returnedAmount != amount))) {
        return _uncertain(
          'El monto o número devuelto por el POS no coincide. Requiere conciliación.',
        );
      }
      final message = _text(response, 'ResponseMessage', 'Message');
      final authorization = _text(response, 'AuthorizationCode');
      final operation = _text(response, 'OperationId', 'OperationID');
      final reference = operation.isNotEmpty
          ? operation
          : authorization.isNotEmpty
          ? authorization
          : ticket;
      return PaymentResult(
        approved: code == 0,
        authorizationCode: reference,
        message: code == 1006
            ? 'Pago cancelado en el terminal'
            : message.isEmpty
            ? 'Respuesta del POS: $code'
            : message,
        outcomeCertain: code != -1,
        cancelled: code == 1006,
        getnetTransaction: GetnetTransactionData(
          responseCode: code,
          responseMessage: message,
          commerceCode: _text(response, 'CommerceCode'),
          terminalId: _text(response, 'TerminalId', 'TerminalID'),
          ticket: returnedTicket.isEmpty ? ticket : returnedTicket,
          authorizationCode: authorization,
          operationId: operation,
          amount: returnedAmount > 0 ? returnedAmount : amount,
          cardBrand: _text(response, 'CardBrand'),
          cardType: _text(response, 'CardType'),
          last4Digits: _text(response, 'Last4Digits'),
          transactionDate: _text(
            response,
            'AccountingDate',
            'RealDate',
            'DateTime',
          ),
        ),
      );
    } on MissingPluginException {
      return const PaymentResult(
        approved: false,
        authorizationCode: '',
        message: 'Integración Getnet para Windows no disponible.',
        outcomeCertain: false,
      );
    } on PlatformException catch (error) {
      return _uncertain(error.message ?? 'Falló la comunicación con el POS.');
    } on FormatException catch (error) {
      return _uncertain('No se pudo verificar la respuesta del POS: $error');
    }
  }

  @override
  Future<PaymentCancellationResult> cancelActivePayment() async {
    try {
      final response = await channel.invokeMapMethod<String, dynamic>(
        'cancelSale',
        {
          'payload': signedCommand({
            'Command': 116,
            'DateTime': DateTime.now().toIso8601String(),
          }),
        },
      );
      return PaymentCancellationResult(
        accepted: response?['accepted'] == true,
        message: response?['message']?.toString(),
      );
    } on PlatformException catch (error) {
      return PaymentCancellationResult(
        accepted: false,
        message: error.message ?? 'No se pudo enviar la cancelación.',
      );
    } on MissingPluginException {
      return const PaymentCancellationResult(
        accepted: false,
        message: 'Integración Getnet para Windows no disponible.',
      );
    }
  }

  static String signedCommand(Map<String, dynamic> command) {
    final serialized = jsonEncode(command);
    return jsonEncode({
      'JsonSerialized': serialized,
      'Sign': sha256.convert(utf8.encode(serialized)).toString().toUpperCase(),
    });
  }

  static Map<String, dynamic> verifySignedResponse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Sobre JSON inválido.');
    }
    final signedValue = decoded['JsonSerialized'];
    final signed = switch (signedValue) {
      String value => value,
      Map<String, dynamic> value => jsonEncode(value),
      _ => throw const FormatException('No llegó el JSON firmado.'),
    };
    final expected = sha256.convert(utf8.encode(signed)).toString();
    if (expected.toUpperCase() != decoded['Sign']?.toString().toUpperCase()) {
      throw const FormatException('Firma SHA-256 inválida.');
    }
    final body = jsonDecode(signed);
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Respuesta Getnet inválida.');
    }
    return body;
  }

  static PaymentResult _uncertain(String message) => PaymentResult(
    approved: false,
    authorizationCode: '',
    message: '$message No vuelvas a cobrar antes de conciliar.',
    outcomeCertain: false,
  );

  static String _text(Map<String, dynamic> values, String key, [
    String? alternative,
    String? third,
  ]) {
    for (final name in [key, alternative, third]) {
      if (name == null) continue;
      final value = values[name]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static int _integer(
    Map<String, dynamic> values,
    String key, {
    int fallback = 0,
  }) {
    final value = values[key];
    return value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
  }
}
