class GournetApiConfig {
  const GournetApiConfig._();

  static final catalogUri = Uri.parse(
    'https://atm.novelty8.com/webhook/api/gournet/v1/catalogo/',
  );
  static final createOrderUri = Uri.parse(
    'https://atm.novelty8.com/webhook/api/gournet/v1/'
    'comercio-virtual/crear-pedido/directa',
  );
  static final branchesUri = Uri.parse(
    'https://atm.novelty8.com/webhook/api/gournet/v1/sucursales',
  );
  static final activationUri = Uri.parse(
    'https://atm.novelty8.com/webhook/api/gournet/v1/iot/activacion/',
  );

  // Una instalación nueva parte sin credenciales y sólo se activa después de
  // validar la API Key en el onboarding.
  static const fallbackApiKey = '';

  @Deprecated('Use the API key stored in DeviceConfig.')
  static const apiKey = fallbackApiKey;

  static const catalogSyncInterval = Duration(minutes: 5);
  static const orderSyncInterval = Duration(minutes: 1);
  static const requestTimeout = Duration(seconds: 15);
  static const branchCode = '';
  static const kioskId = 'totem-001';
}
