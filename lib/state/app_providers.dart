import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock/mock_dte_service.dart';
import '../data/mock/mock_hardware_services.dart';
import '../data/mock/mock_payment_gateway.dart';
import '../data/mock/mock_printer_service.dart';
import '../data/local/payment_audit_repository.dart';
import '../data/remote/gournet_catalog_repository.dart';
import '../data/remote/gournet_order_repository.dart';
import '../domain/models/device_config.dart';
import '../domain/repositories/catalog_repository.dart';
import '../domain/repositories/order_repository.dart';
import '../services/dte/dte_service.dart';
import '../services/nfc/nfc_service.dart';
import '../services/payment/getnet_usb_payment_gateway.dart';
import '../services/payment/windows_getnet_payment_gateway.dart';
import '../services/payment/payment_gateway.dart';
import '../services/printer/printer_service.dart';
import '../services/printer/sunmi_printer_service.dart';
import '../services/scanner/scanner_service.dart';
import '../services/speaker/speaker_service.dart';
import 'device_config_controller.dart';

final paymentAuditRepositoryProvider = Provider<PaymentAuditRepository>(
  (ref) => PaymentAuditRepository(),
);

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  final config = ref.watch(deviceConfigProvider);
  final repository = GournetCatalogRepository(
    apiKey: config.apiKey,
    // GET /catalogo/ recibe el mismo TUS alfanumérico que crear-pedido.
    tus: config.branchCode,
    endpoint: Uri.parse(config.catalogEndpoint),
  );
  ref.onDispose(repository.dispose);
  return repository;
});
final catalogProvider = FutureProvider<CatalogData>((ref) {
  final config = ref.watch(deviceConfigProvider);
  final timer = Timer.periodic(
    Duration(minutes: config.catalogSyncMinutes),
    (_) => ref.invalidateSelf(),
  );
  ref.onDispose(timer.cancel);
  return ref.watch(catalogRepositoryProvider).loadCatalog();
});
final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  final config = ref.watch(deviceConfigProvider);
  final repository = GournetOrderRepository(
    apiKey: config.apiKey,
    // La API de pedidos espera el TUS alfanumérico de la sucursal.
    tus: config.branchCode,
    branchCode: config.branchCode,
    kioskId: config.kioskId,
    endpoint: Uri.parse(config.createOrderEndpoint),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final orderSyncProvider = Provider<void>((ref) {
  final config = ref.watch(deviceConfigProvider);
  final repository = ref.watch(orderRepositoryProvider);
  unawaited(repository.syncPending());
  final timer = Timer.periodic(
    Duration(minutes: config.orderSyncMinutes),
    (_) => unawaited(repository.syncPending()),
  );
  ref.onDispose(timer.cancel);
});

final paymentGatewayProvider = Provider<PaymentGateway>((ref) {
  final config = ref.watch(deviceConfigProvider);
  if (config.paymentProvider != 'simulator') {
    if (Platform.isWindows) {
      return WindowsGetnetPaymentGateway(port: config.windowsGetnetPort);
    }
    return const GetnetUsbPaymentGateway();
  }
  return MockGetnetGateway(
    shouldApprove: config.paymentOutcome == MockPaymentOutcome.approved,
  );
});

final dteServiceProvider = Provider<DteService>((ref) {
  final config = ref.watch(deviceConfigProvider);
  return MockDteService(
    shouldSucceed: config.dteOutcome == MockDteOutcome.success,
  );
});

final printerServiceProvider = Provider<PrinterService>((ref) {
  final config = ref.watch(deviceConfigProvider);
  if (config.printerState == MockPrinterState.noPaper) {
    return const MockPrinterService(hasPaper: false);
  }
  return SunmiPrinterService(
    restaurantName: config.restaurantName,
    windowsPrinterName: config.windowsPrinterName,
  );
});

final scannerServiceProvider = Provider<ScannerService>(
  (ref) => MockScannerService(),
);
final nfcServiceProvider = Provider<NfcService>((ref) => MockNfcService());
final speakerServiceProvider = Provider<SpeakerService>(
  (ref) => MockSpeakerService(),
);
