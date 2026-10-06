enum OperatingMode { standalone, integrated }

enum MockPaymentOutcome { approved, declined }

enum MockPrinterState { ready, noPaper }

enum MockDteOutcome { success, error }

enum PaymentTerminalSide { left, right }

enum PaymentTerminalVerticalPosition { center, bottom }

class DeviceConfig {
  const DeviceConfig({
    this.deviceId = 'SUNMI-K2-DEMO',
    this.kioskId = 'totem-001',
    this.branchId = '',
    this.branchCode = '',
    this.branchName = '',
    this.operatingMode = OperatingMode.integrated,
    this.restaurantName = 'Restaurant Demo',
    this.logo = '',
    this.primaryColor = '#E5187E',
    this.allowEatIn = true,
    this.allowTakeAway = true,
    this.idleTimeoutSeconds = 60,
    this.catalogSyncMinutes = 5,
    this.orderSyncMinutes = 1,
    this.nextOrderNumber = 0,
    this.catalogEndpoint =
        'https://atm.novelty8.com/webhook/api/gournet/v1/catalogo/',
    this.createOrderEndpoint = 'https://atm.novelty8.com/webhook/api/gournet/v1/comercio-virtual/crear-pedido/directa',
    this.branchesEndpoint =
        'https://atm.novelty8.com/webhook/api/gournet/v1/sucursales',
    this.activationEndpoint =
        'https://atm.novelty8.com/webhook/api/gournet/v1/iot/activacion/',
    this.apiKey = '',
    this.adminPinHash = '',
    this.catalogVersion = 'remote-v1',
    this.paymentProvider = 'getnet_usb',
    this.windowsGetnetPort = '',
    this.windowsPrinterName = '',
    this.paymentTerminalSide = PaymentTerminalSide.right,
    this.paymentTerminalVerticalPosition =
        PaymentTerminalVerticalPosition.center,
    this.online = true,
    this.autoUpdates = true,
    this.paymentOutcome = MockPaymentOutcome.approved,
    this.printerState = MockPrinterState.ready,
    this.dteOutcome = MockDteOutcome.success,
  });

  final String deviceId;
  final String kioskId;

  /// _ID interno conservado sólo como referencia de la sucursal seleccionada.
  final String branchId;

  /// TUS alfanumérico usado para consultar el catálogo y enviar pedidos.
  final String branchCode;
  final String branchName;
  final OperatingMode operatingMode;
  final String restaurantName;
  final String logo;
  final String primaryColor;
  final bool allowEatIn;
  final bool allowTakeAway;
  final int idleTimeoutSeconds;
  final int catalogSyncMinutes;
  final int orderSyncMinutes;

  /// Próximo correlativo que se asignará. La primera venta utiliza el número 0.
  final int nextOrderNumber;
  final String catalogEndpoint;
  final String createOrderEndpoint;
  final String branchesEndpoint;
  final String activationEndpoint;
  final String apiKey;
  final String adminPinHash;
  final String catalogVersion;
  final String paymentProvider;
  /// Puerto COM del IM30 en Windows. Vacío: autodetección PAX por VID/PID.
  final String windowsGetnetPort;
  /// Nombre exacto de la impresora térmica instalada en Windows.
  final String windowsPrinterName;
  final PaymentTerminalSide paymentTerminalSide;
  final PaymentTerminalVerticalPosition paymentTerminalVerticalPosition;
  final bool online;
  final bool autoUpdates;
  final MockPaymentOutcome paymentOutcome;
  final MockPrinterState printerState;
  final MockDteOutcome dteOutcome;

  bool get isActivated =>
      apiKey.trim().isNotEmpty && branchCode.trim().isNotEmpty;

  DeviceConfig copyWith({
    String? deviceId,
    String? kioskId,
    String? branchId,
    String? branchCode,
    String? branchName,
    OperatingMode? operatingMode,
    String? restaurantName,
    String? logo,
    String? primaryColor,
    bool? allowEatIn,
    bool? allowTakeAway,
    int? idleTimeoutSeconds,
    int? catalogSyncMinutes,
    int? orderSyncMinutes,
    int? nextOrderNumber,
    String? catalogEndpoint,
    String? createOrderEndpoint,
    String? branchesEndpoint,
    String? activationEndpoint,
    String? apiKey,
    String? adminPinHash,
    String? catalogVersion,
    String? paymentProvider,
    String? windowsGetnetPort,
    String? windowsPrinterName,
    PaymentTerminalSide? paymentTerminalSide,
    PaymentTerminalVerticalPosition? paymentTerminalVerticalPosition,
    bool? online,
    bool? autoUpdates,
    MockPaymentOutcome? paymentOutcome,
    MockPrinterState? printerState,
    MockDteOutcome? dteOutcome,
  }) => DeviceConfig(
    deviceId: deviceId ?? this.deviceId,
    kioskId: kioskId ?? this.kioskId,
    branchId: branchId ?? this.branchId,
    branchCode: branchCode ?? this.branchCode,
    branchName: branchName ?? this.branchName,
    operatingMode: operatingMode ?? this.operatingMode,
    restaurantName: restaurantName ?? this.restaurantName,
    logo: logo ?? this.logo,
    primaryColor: primaryColor ?? this.primaryColor,
    allowEatIn: allowEatIn ?? this.allowEatIn,
    allowTakeAway: allowTakeAway ?? this.allowTakeAway,
    idleTimeoutSeconds: idleTimeoutSeconds ?? this.idleTimeoutSeconds,
    catalogSyncMinutes: catalogSyncMinutes ?? this.catalogSyncMinutes,
    orderSyncMinutes: orderSyncMinutes ?? this.orderSyncMinutes,
    nextOrderNumber: nextOrderNumber ?? this.nextOrderNumber,
    catalogEndpoint: catalogEndpoint ?? this.catalogEndpoint,
    createOrderEndpoint: createOrderEndpoint ?? this.createOrderEndpoint,
    branchesEndpoint: branchesEndpoint ?? this.branchesEndpoint,
    activationEndpoint: activationEndpoint ?? this.activationEndpoint,
    apiKey: apiKey ?? this.apiKey,
    adminPinHash: adminPinHash ?? this.adminPinHash,
    catalogVersion: catalogVersion ?? this.catalogVersion,
    paymentProvider: paymentProvider ?? this.paymentProvider,
    windowsGetnetPort: windowsGetnetPort ?? this.windowsGetnetPort,
    windowsPrinterName: windowsPrinterName ?? this.windowsPrinterName,
    paymentTerminalSide: paymentTerminalSide ?? this.paymentTerminalSide,
    paymentTerminalVerticalPosition:
        paymentTerminalVerticalPosition ?? this.paymentTerminalVerticalPosition,
    online: online ?? this.online,
    autoUpdates: autoUpdates ?? this.autoUpdates,
    paymentOutcome: paymentOutcome ?? this.paymentOutcome,
    printerState: printerState ?? this.printerState,
    dteOutcome: dteOutcome ?? this.dteOutcome,
  );

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'kioskId': kioskId,
    'branchId': branchId,
    'branchCode': branchCode,
    'branchName': branchName,
    'operatingMode': operatingMode.name,
    'restaurantName': restaurantName,
    'logo': logo,
    'primaryColor': primaryColor,
    'allowEatIn': allowEatIn,
    'allowTakeAway': allowTakeAway,
    'idleTimeoutSeconds': idleTimeoutSeconds,
    'catalogSyncMinutes': catalogSyncMinutes,
    'orderSyncMinutes': orderSyncMinutes,
    'nextOrderNumber': nextOrderNumber,
    'catalogEndpoint': catalogEndpoint,
    'createOrderEndpoint': createOrderEndpoint,
    'branchesEndpoint': branchesEndpoint,
    'activationEndpoint': activationEndpoint,
    'catalogVersion': catalogVersion,
    'paymentProvider': paymentProvider,
    'windowsGetnetPort': windowsGetnetPort,
    'windowsPrinterName': windowsPrinterName,
    'paymentTerminalSide': paymentTerminalSide.name,
    'paymentTerminalVerticalPosition': paymentTerminalVerticalPosition.name,
    'online': online,
    'autoUpdates': autoUpdates,
    'paymentOutcome': paymentOutcome.name,
    'printerState': printerState.name,
    'dteOutcome': dteOutcome.name,
  };

  factory DeviceConfig.fromJson(
    Map<String, dynamic> json, {
    required String apiKey,
    required String adminPinHash,
  }) {
    const defaults = DeviceConfig();
    T enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
      for (final value in values) {
        if (value.name == raw) return value;
      }
      return fallback;
    }

    String text(String key, String fallback) {
      final value = json[key]?.toString().trim() ?? '';
      return value.isEmpty ? fallback : value;
    }

    int positiveInt(String key, int fallback) {
      final value = int.tryParse(json[key]?.toString() ?? '');
      return value != null && value > 0 ? value : fallback;
    }

    int nonNegativeInt(String key, int fallback) {
      final value = int.tryParse(json[key]?.toString() ?? '');
      return value != null && value >= 0 ? value : fallback;
    }

    return DeviceConfig(
      autoUpdates: json['autoUpdates'] as bool? ?? true,
      deviceId: text('deviceId', defaults.deviceId),
      kioskId: text('kioskId', defaults.kioskId),
      branchId: text('branchId', defaults.branchId),
      branchCode: text('branchCode', defaults.branchCode),
      branchName: text('branchName', defaults.branchName),
      operatingMode: enumValue(
        OperatingMode.values,
        json['operatingMode'],
        defaults.operatingMode,
      ),
      restaurantName: text('restaurantName', defaults.restaurantName),
      logo: json['logo']?.toString() ?? defaults.logo,
      primaryColor: text('primaryColor', defaults.primaryColor),
      allowEatIn: json['allowEatIn'] as bool? ?? defaults.allowEatIn,
      allowTakeAway: json['allowTakeAway'] as bool? ?? defaults.allowTakeAway,
      idleTimeoutSeconds: positiveInt(
        'idleTimeoutSeconds',
        defaults.idleTimeoutSeconds,
      ),
      catalogSyncMinutes: positiveInt(
        'catalogSyncMinutes',
        defaults.catalogSyncMinutes,
      ),
      orderSyncMinutes: positiveInt(
        'orderSyncMinutes',
        defaults.orderSyncMinutes,
      ),
      nextOrderNumber: nonNegativeInt(
        'nextOrderNumber',
        defaults.nextOrderNumber,
      ),
      catalogEndpoint: text('catalogEndpoint', defaults.catalogEndpoint),
      createOrderEndpoint: text(
        'createOrderEndpoint',
        defaults.createOrderEndpoint,
      ),
      branchesEndpoint: text('branchesEndpoint', defaults.branchesEndpoint),
      activationEndpoint: text(
        'activationEndpoint',
        defaults.activationEndpoint,
      ),
      apiKey: apiKey,
      adminPinHash: adminPinHash,
      catalogVersion: text('catalogVersion', defaults.catalogVersion),
      paymentProvider: text('paymentProvider', defaults.paymentProvider),
      windowsGetnetPort:
          json['windowsGetnetPort']?.toString().trim() ?? '',
      windowsPrinterName:
          json['windowsPrinterName']?.toString().trim() ?? '',
      paymentTerminalSide: enumValue(
        PaymentTerminalSide.values,
        json['paymentTerminalSide'],
        defaults.paymentTerminalSide,
      ),
      paymentTerminalVerticalPosition: enumValue(
        PaymentTerminalVerticalPosition.values,
        json['paymentTerminalVerticalPosition'],
        defaults.paymentTerminalVerticalPosition,
      ),
      online: json['online'] as bool? ?? defaults.online,
      paymentOutcome: enumValue(
        MockPaymentOutcome.values,
        json['paymentOutcome'],
        defaults.paymentOutcome,
      ),
      printerState: enumValue(
        MockPrinterState.values,
        json['printerState'],
        defaults.printerState,
      ),
      dteOutcome: enumValue(
        MockDteOutcome.values,
        json['dteOutcome'],
        defaults.dteOutcome,
      ),
    );
  }
}
