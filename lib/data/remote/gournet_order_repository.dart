import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/config/gournet_api_config.dart';
import '../../domain/models/order.dart';
import '../../domain/repositories/order_repository.dart';

typedef OrderDirectoryResolver = Future<Directory> Function();

class GournetOrderRepository implements OrderRepository {
  GournetOrderRepository({
    this.apiKey = GournetApiConfig.apiKey,
    this.branchCode = GournetApiConfig.branchCode,
    String? tus,
    this.kioskId = GournetApiConfig.kioskId,
    Uri? endpoint,
    this.requestTimeout = GournetApiConfig.requestTimeout,
    http.Client? client,
    OrderDirectoryResolver? storageDirectory,
  }) : endpoint = endpoint ?? GournetApiConfig.createOrderUri,
       tus = tus == null || tus.trim().isEmpty ? branchCode : tus,
       _client = client ?? http.Client(),
       _storageDirectory = storageDirectory ?? getApplicationSupportDirectory;

  static const _queueVersion = 1;
  static const _queueFilename = 'gournet-order-outbox.json';

  final String apiKey;

  /// Identificador TUS que acepta crear-pedido/directa. En la configuración
  /// corresponde a `branchCode` (por ejemplo, `5QQTw5u1K8ed`).
  final String tus;

  /// Alias conservado por compatibilidad con versiones anteriores.
  final String branchCode;
  final String kioskId;
  final Uri endpoint;
  final Duration requestTimeout;
  final http.Client _client;
  final OrderDirectoryResolver _storageDirectory;

  Future<void> _operationTail = Future<void>.value();

  void dispose() => _client.close();

  @override
  Future<void> save(Order order) async {
    final payload = buildPayload(order);
    try {
      await _exclusive(() async {
        final directory = await _resolveStorageDirectory();
        final queued = await _readQueue(directory);
        final idempotencyKey = payload['idempotency_key'];
        if (!queued.any((item) => item['idempotency_key'] == idempotencyKey)) {
          queued.add(payload);
          await _writeQueue(directory, queued);
        }
        await _syncLocked(directory);
      });
    } catch (_) {
      // Si el almacenamiento del dispositivo no está disponible, todavía se
      // intenta el envío inmediato. El checkout no debe revertir un pago ya
      // aprobado por un fallo de conectividad posterior.
      await _send(payload);
    }
  }

  @override
  Future<void> syncPending() async {
    try {
      await _exclusive(() async {
        final directory = await _resolveStorageDirectory();
        await _syncLocked(directory);
      });
    } catch (_) {
      // La cola permanece intacta para el siguiente intento periódico.
    }
  }

  Map<String, dynamic> buildPayload(Order order) {
    final externalNumber = order.number.toString();
    final createdAt = _apiDate(order.createdAt);

    return {
      'tus': tus,
      'numero': externalNumber,
      'origen_id': '$kioskId-$externalNumber',
      'idempotency_key': order.uuid,
      'tipo_entrega': order.type == OrderType.eatIn ? 'mesa' : 'retiro',
      'tiempo_estimado_min': '',
      'programado_para': '',
      'origen_creado_en': createdAt,
      'subtotal': order.subtotal.toString(),
      'descuento': '0',
      'costo_envio': '0',
      'propina': '0',
      'comision_canal': '0',
      'total': order.total.toString(),
      'moneda': 'CLP',
      'estado_pago': 'pagado',
      'metodo_pago': 'app',
      'pago_referencia': order.paymentReference,
      'pagado_en': createdAt,
      'nota_interna': _internalNote(order),
      'productos': order.items
          .map((item) {
            final numericId = int.tryParse(item.product.id);
            return {
              'producto_id': numericId ?? item.product.id,
              'sku': item.product.sku,
              'nombre': item.product.name,
              'cantidad': item.quantity,
              'precio_unitario': item.unitPrice,
              'total_linea': item.total,
              'modificadores': item.modifiers
                  .map((modifier) => modifier.optionName)
                  .join(', '),
              'nota': '',
            };
          })
          .toList(growable: false),
    };
  }

  String _internalNote(Order order) {
    if (order.total == 0) {
      return 'Pedido sin cobro (total 0) generado por Gour-net Kiosk $kioskId.';
    }
    final getnet = order.getnetTransaction;
    if (getnet == null) return 'Pedido generado por Gour-net Kiosk $kioskId.';
    return 'Pedido generado por Gour-net Kiosk $kioskId. '
        'Getnet terminal=${getnet.terminalId}, operacion=${getnet.operationId}, '
        'autorizacion=${getnet.authorizationCode}, ticket=${getnet.ticket}.';
  }

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

  Future<Directory> _resolveStorageDirectory() async {
    final directory = await _storageDirectory();
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<List<Map<String, dynamic>>> _readQueue(Directory directory) async {
    final file = File('${directory.path}/$_queueFilename');
    if (!await file.exists()) return [];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != _queueVersion ||
        decoded['orders'] is! List<dynamic>) {
      throw const FormatException('La cola local de pedidos no es válida.');
    }
    return (decoded['orders'] as List<dynamic>)
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }

  Future<void> _writeQueue(
    Directory directory,
    List<Map<String, dynamic>> orders,
  ) async {
    final target = File('${directory.path}/$_queueFilename');
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'version': _queueVersion, 'orders': orders}),
      flush: true,
    );
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  Future<void> _syncLocked(Directory directory) async {
    final queued = await _readQueue(directory);
    if (queued.isEmpty) return;

    final pending = <Map<String, dynamic>>[];
    for (final queuedPayload in queued) {
      final payload = _normalizeQueuedPayload(queuedPayload);
      if (!await _send(payload)) pending.add(payload);
    }
    if (pending.length != queued.length) {
      await _writeQueue(directory, pending);
    }
  }

  Map<String, dynamic> _normalizeQueuedPayload(
    Map<String, dynamic> queuedPayload,
  ) {
    final payload = Map<String, dynamic>.from(queuedPayload);
    // Las versiones anteriores guardaban el campo como `sucursal`, cuyo
    // valor podía ser el `_ID` interno. Al migrar, el único valor válido para
    // la API es el TUS configurado actualmente.
    final legacyBranch = payload.remove('sucursal');
    if (legacyBranch != null) {
      payload['tus'] = tus;
    } else if (payload['tus']?.toString().trim().isNotEmpty != true) {
      payload['tus'] = tus;
    }
    payload.remove('items_count');
    final originalCreatedAt = payload['origen_creado_en']?.toString() ?? '';
    final currentNumber = payload['numero']?.toString() ?? '';
    if (currentNumber.isEmpty || int.tryParse(currentNumber) == null) {
      final migratedNumber = originalCreatedAt.replaceAll(RegExp(r'\D'), '');
      if (migratedNumber.isNotEmpty) {
        payload['numero'] = migratedNumber;
        payload['origen_id'] = '$kioskId-$migratedNumber';
      }
    }
    final paymentReference = payload['pago_referencia']?.toString() ?? '';
    if (paymentReference.isEmpty || int.tryParse(paymentReference) == null) {
      final seed = payload['idempotency_key']?.toString() ?? paymentReference;
      payload['pago_referencia'] = _numericReference(seed);
    }
    for (final field in const ['origen_creado_en', 'pagado_en']) {
      final value = payload[field]?.toString() ?? '';
      if (value.length >= 16) {
        payload[field] = value.substring(0, 16).replaceFirst(' ', 'T');
      }
    }
    return payload;
  }

  Future<bool> _send(Map<String, dynamic> payload) async {
    try {
      developer.log(
        'POST $endpoint idempotency=${payload['idempotency_key']}',
        name: 'gournet.orders',
      );
      final response = await _client
          .post(
            endpoint,
            headers: {
              'accept': 'application/json',
              'content-type': 'application/json',
              'apiKey': apiKey,
            },
            body: jsonEncode(payload),
          )
          .timeout(requestTimeout);
      developer.log(
        'HTTP ${response.statusCode} body=${response.body}',
        name: 'gournet.orders',
      );
      return response.statusCode >= HttpStatus.ok &&
          response.statusCode < HttpStatus.multipleChoices;
    } catch (error, stackTrace) {
      developer.log(
        'POST failed: $error',
        name: 'gournet.orders',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  String _apiDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}T'
        '${two(date.hour)}:${two(date.minute)}';
  }

  String _numericReference(String seed) => seed.codeUnits
      .fold<int>(0, (value, unit) => (value * 31 + unit) % 100000000)
      .toString()
      .padLeft(8, '0');
}
