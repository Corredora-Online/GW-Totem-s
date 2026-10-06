import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/order.dart';
import '../../services/payment/payment_gateway.dart';

typedef PaymentAuditDirectoryResolver = Future<Directory> Function();

enum PaymentAuditStatus {
  processing,
  cancellationRequested,
  approved,
  declined,
  cancelled,
  uncertain,
}

class PaymentAuditBeginResult {
  const PaymentAuditBeginResult._({
    required this.allowed,
    this.entryId,
    this.message,
  });

  const PaymentAuditBeginResult.allowed(String entryId)
    : this._(allowed: true, entryId: entryId);

  const PaymentAuditBeginResult.blocked(String message)
    : this._(allowed: false, message: message);

  final bool allowed;
  final String? entryId;
  final String? message;
}

/// Registro local duradero de cada intento Getnet.
///
/// No almacena PAN, fecha de vencimiento, PIN ni ningún dato sensible de la
/// tarjeta. Conserva sólo identificadores y los últimos cuatro dígitos que el
/// POS devuelve para conciliación.
class PaymentAuditRepository {
  PaymentAuditRepository({PaymentAuditDirectoryResolver? storageDirectory})
    : _storageDirectory = storageDirectory ?? getApplicationSupportDirectory;

  static const filename = 'gournet-payment-audit.json';
  static const _version = 1;

  final PaymentAuditDirectoryResolver _storageDirectory;
  Future<void> _operationTail = Future<void>.value();

  Future<PaymentAuditBeginResult> begin({
    required String transactionId,
    required int orderNumber,
    required int amount,
  }) => _exclusive(() async {
    final directory = await _directory();
    final entries = await _read(directory);
    final unresolved = entries.where((entry) {
      return const {
        'processing',
        'cancellationRequested',
        'uncertain',
      }.contains(entry['status']);
    }).firstOrNull;
    if (unresolved != null) {
      return const PaymentAuditBeginResult.blocked(
        'Existe un pago pendiente de conciliación. Solicita asistencia antes de reintentar.',
      );
    }
    final approvedDuplicate = entries.where((entry) {
      final samePayment = entry['transactionId'] == transactionId;
      final sameOrder = entry['orderNumber'] == orderNumber;
      if (!samePayment && !sameOrder) return false;
      return entry['status'] == PaymentAuditStatus.approved.name;
    }).firstOrNull;
    if (approvedDuplicate != null) {
      return const PaymentAuditBeginResult.blocked(
        'Este pedido ya tiene un pago aprobado. No se realizará otro cobro.',
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final entryId = const Uuid().v4();
    entries.add({
      'entryId': entryId,
      'transactionId': transactionId,
      'orderNumber': orderNumber,
      'amount': amount,
      'status': PaymentAuditStatus.processing.name,
      'startedAt': now,
      'updatedAt': now,
      'outcomeCertain': false,
    });
    await _write(directory, entries);
    return PaymentAuditBeginResult.allowed(entryId);
  });

  Future<void> markCancellationRequested(String entryId) => _update(
    entryId,
    (entry) => {
      ...entry,
      'status': PaymentAuditStatus.cancellationRequested.name,
      'cancellationRequestedAt': DateTime.now().toUtc().toIso8601String(),
    },
  );

  Future<void> complete(String entryId, PaymentResult result) =>
      _update(entryId, (entry) {
        final transaction = result.getnetTransaction;
        final status = result.approved
            ? PaymentAuditStatus.approved
            : !result.outcomeCertain
            ? PaymentAuditStatus.uncertain
            : result.cancelled
            ? PaymentAuditStatus.cancelled
            : PaymentAuditStatus.declined;
        return {
          ...entry,
          'status': status.name,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'outcomeCertain': result.outcomeCertain,
          'message': result.message ?? '',
          'paymentReference': result.authorizationCode,
          if (transaction != null) 'getnet': _getnetJson(transaction),
        };
      });

  Future<List<Map<String, dynamic>>> readAll() => _exclusive(() async {
    final entries = await _read(await _directory());
    return entries.reversed
        .map((entry) => Map<String, dynamic>.unmodifiable(entry))
        .toList(growable: false);
  });

  Future<void> resolveManually(
    String entryId, {
    required bool paymentConfirmed,
  }) => _update(
    entryId,
    (entry) => {
      ...entry,
      'status': paymentConfirmed
          ? PaymentAuditStatus.approved.name
          : PaymentAuditStatus.declined.name,
      'outcomeCertain': true,
      'manualResolution': paymentConfirmed
          ? 'paymentConfirmed'
          : 'noChargeConfirmed',
      'manuallyResolvedAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    },
  );

  Future<void> _update(
    String entryId,
    Map<String, dynamic> Function(Map<String, dynamic>) transform,
  ) => _exclusive(() async {
    final directory = await _directory();
    final entries = await _read(directory);
    final index = entries.indexWhere((entry) => entry['entryId'] == entryId);
    if (index < 0) return;
    entries[index] = transform(entries[index]);
    await _write(directory, entries);
  });

  Map<String, dynamic> _getnetJson(GetnetTransactionData data) => {
    'responseCode': data.responseCode,
    'responseMessage': data.responseMessage,
    'commerceCode': data.commerceCode,
    'terminalId': data.terminalId,
    'ticket': data.ticket,
    'authorizationCode': data.authorizationCode,
    'operationId': data.operationId,
    'amount': data.amount,
    'cardBrand': data.cardBrand,
    'cardType': data.cardType,
    'last4Digits': data.last4Digits,
    'transactionDate': data.transactionDate,
  };

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    final previous = _operationTail;
    final gate = Completer<void>();
    _operationTail = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }

  Future<Directory> _directory() async {
    final directory = await _storageDirectory();
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<List<Map<String, dynamic>>> _read(Directory directory) async {
    final file = File('${directory.path}/$filename');
    if (!await file.exists()) return [];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != _version ||
        decoded['entries'] is! List<dynamic>) {
      throw const FormatException('El registro local de pagos no es válido.');
    }
    return (decoded['entries'] as List<dynamic>)
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (entry) => entry.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }

  Future<void> _write(
    Directory directory,
    List<Map<String, dynamic>> entries,
  ) async {
    final target = File('${directory.path}/$filename');
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'version': _version, 'entries': entries}),
      flush: true,
    );
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }
}
