import 'package:flutter/services.dart';

import '../../core/formatting/money.dart';
import '../../domain/models/order.dart';
import 'printer_service.dart';

class SunmiPrinterService implements PrinterService {
  const SunmiPrinterService({
    this.restaurantName = 'GOUR-NET',
    this.windowsPrinterName = '',
  });

  final String restaurantName;
  final String windowsPrinterName;

  static const _channel = MethodChannel('cl.gournet.kiosk/printer');
  static const _lineWidth = 42;

  @override
  Future<PrintResult> print(Order order) async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'printReceipt',
        {
          'header': restaurantName,
          'printerName': windowsPrinterName,
          'orderNumber': order.number.toString(),
          'body': _buildBody(order),
          'footer':
              'NO VALIDO COMO DOCUMENTO TRIBUTARIO\nGracias por tu compra',
        },
      );
      return PrintResult(
        success: response?['success'] == true,
        message: response?['message'] as String?,
      );
    } on MissingPluginException {
      return const PrintResult(
        success: false,
        message: 'Servicio de impresión no disponible en esta plataforma',
      );
    } on PlatformException catch (error) {
      return PrintResult(success: false, message: error.message);
    }
  }

  String _buildBody(Order order) {
    final buffer = StringBuffer()
      ..writeln('=' * _lineWidth)
      ..writeln(_center('COMPROBANTE DE PEDIDO'))
      ..writeln('=' * _lineWidth)
      ..writeln(
        _row(
          'Tipo',
          order.type == OrderType.takeAway ? 'Para llevar' : 'Comer aqui',
        ),
      )
      ..writeln(_row('Fecha', _formatDate(order.createdAt)))
      ..writeln('-' * _lineWidth);

    for (final item in order.items) {
      buffer.writeln('${item.quantity} x ${item.product.name}');
      if (item.modifiers.isNotEmpty) {
        buffer.writeln(
          '  ${item.modifiers.map((item) => item.optionName).join(', ')}',
        );
      }
      buffer.writeln(_row('', formatClp(item.total)));
    }

    buffer
      ..writeln('-' * _lineWidth)
      ..writeln(_row('TOTAL', formatClp(order.total)))
      ..writeln('-' * _lineWidth)
      ..writeln(
        _center(order.total == 0 ? 'PEDIDO SIN COBRO' : 'PAGO GETNET APROBADO'),
      );
    final getnet = order.getnetTransaction;
    if (order.total != 0 && getnet != null) {
      _writeIfPresent(
        buffer,
        'Respuesta',
        '${getnet.responseCode} ${getnet.responseMessage}',
      );
      _writeIfPresent(buffer, 'Comercio', getnet.commerceCode);
      _writeIfPresent(buffer, 'Terminal', getnet.terminalId);
      _writeIfPresent(buffer, 'Operacion', getnet.operationId);
      _writeIfPresent(buffer, 'Autorizacion', getnet.authorizationCode);
      _writeIfPresent(buffer, 'Ticket', getnet.ticket);
      _writeIfPresent(buffer, 'Tarjeta', _cardDescription(getnet));
      _writeIfPresent(buffer, 'Fecha POS', getnet.transactionDate);
      if (getnet.amount > 0) {
        buffer.writeln(_row('Monto POS', formatClp(getnet.amount)));
      }
    } else if (order.total != 0) {
      buffer.writeln(_row('Referencia', order.paymentReference));
    }
    buffer
      ..writeln('-' * _lineWidth)
      ..writeln(_center('DOCUMENTO NO TRIBUTARIO'));
    return buffer.toString();
  }

  void _writeIfPresent(StringBuffer buffer, String label, String value) {
    if (value.trim().isNotEmpty) buffer.writeln(_row(label, value.trim()));
  }

  String _cardDescription(GetnetTransactionData data) {
    final parts = <String>[
      if (data.cardBrand.isNotEmpty) data.cardBrand,
      if (data.cardType.isNotEmpty) data.cardType,
      if (data.last4Digits.isNotEmpty) '**** ${data.last4Digits}',
    ];
    return parts.join(' ');
  }

  String _row(String left, String right) {
    final safeLeft = left.length > _lineWidth
        ? left.substring(0, _lineWidth)
        : left;
    final available = (_lineWidth - safeLeft.length - right.length).clamp(
      1,
      _lineWidth,
    );
    return '$safeLeft${' ' * available}$right';
  }

  String _center(String value) {
    final left = ((_lineWidth - value.length) / 2).floor().clamp(0, _lineWidth);
    return '${' ' * left}$value';
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }
}
