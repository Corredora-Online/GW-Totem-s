import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatting/money.dart';
import '../../core/security/admin_pin.dart';
import '../../core/theme/app_colors.dart';
import '../../data/remote/gournet_branches_repository.dart';
import '../../domain/models/branch.dart';
import '../../domain/models/device_config.dart';
import '../../services/kiosk/kiosk_service.dart';
import '../../state/app_providers.dart';
import '../../state/device_config_controller.dart';
import '../../state/session/session_reset.dart';
import 'update_settings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _branchesRepository = GournetBranchesRepository();
  late final TextEditingController _restaurantName;
  late final TextEditingController _deviceId;
  late final TextEditingController _kioskId;
  late final TextEditingController _branchCode;
  late final TextEditingController _logo;
  late final TextEditingController _primaryColor;
  late final TextEditingController _idleSeconds;
  late final TextEditingController _apiKey;
  late final TextEditingController _catalogEndpoint;
  late final TextEditingController _createOrderEndpoint;
  late final TextEditingController _branchesEndpoint;
  late final TextEditingController _activationEndpoint;
  late final TextEditingController _catalogSyncMinutes;
  late final TextEditingController _orderSyncMinutes;
  late final TextEditingController _catalogVersion;
  late final TextEditingController _windowsGetnetPort;
  late final TextEditingController _windowsPrinterName;
  late String _paymentProvider;
  late final TextEditingController _newPin;
  late final TextEditingController _confirmPin;

  late OperatingMode _operatingMode;
  late MockPaymentOutcome _paymentOutcome;
  late MockPrinterState _printerState;
  late MockDteOutcome _dteOutcome;
  late PaymentTerminalSide _paymentTerminalSide;
  late PaymentTerminalVerticalPosition _paymentTerminalVerticalPosition;
  late bool _online;
  late bool _allowEatIn;
  late bool _allowTakeAway;
  late String _branchId;
  late String _branchName;
  List<Branch> _branches = const [];
  bool _loadingBranches = false;
  bool _saving = false;
  bool _showApiKey = false;
  String? _branchError;
  KioskStatus? _kioskStatus;
  List<String> _windowsPrinters = const [];
  bool _loadingPrinters = false;
  bool _testingPrinter = false;
  static const _printerChannel = MethodChannel('cl.gournet.kiosk/printer');

  @override
  void initState() {
    super.initState();
    final config = ref.read(deviceConfigProvider);
    _restaurantName = TextEditingController(text: config.restaurantName);
    _deviceId = TextEditingController(text: config.deviceId);
    _kioskId = TextEditingController(text: config.kioskId);
    _branchCode = TextEditingController(text: config.branchCode);
    _logo = TextEditingController(text: config.logo);
    _primaryColor = TextEditingController(text: config.primaryColor);
    _idleSeconds = TextEditingController(text: '${config.idleTimeoutSeconds}');
    _apiKey = TextEditingController(text: config.apiKey);
    _catalogEndpoint = TextEditingController(text: config.catalogEndpoint);
    _createOrderEndpoint = TextEditingController(
      text: config.createOrderEndpoint,
    );
    _branchesEndpoint = TextEditingController(text: config.branchesEndpoint);
    _activationEndpoint = TextEditingController(
      text: config.activationEndpoint,
    );
    _catalogSyncMinutes = TextEditingController(
      text: '${config.catalogSyncMinutes}',
    );
    _orderSyncMinutes = TextEditingController(
      text: '${config.orderSyncMinutes}',
    );
    _catalogVersion = TextEditingController(text: config.catalogVersion);
    _windowsGetnetPort = TextEditingController(text: config.windowsGetnetPort);
    _windowsPrinterName = TextEditingController(
      text: config.windowsPrinterName,
    );
    _paymentProvider = config.paymentProvider == 'simulator'
        ? 'simulator'
        : 'getnet_usb';
    _newPin = TextEditingController();
    _confirmPin = TextEditingController();
    _operatingMode = config.operatingMode;
    _paymentOutcome = config.paymentOutcome;
    _printerState = config.printerState;
    _dteOutcome = config.dteOutcome;
    _paymentTerminalSide = config.paymentTerminalSide;
    _paymentTerminalVerticalPosition = config.paymentTerminalVerticalPosition;
    _online = config.online;
    _allowEatIn = config.allowEatIn;
    _allowTakeAway = config.allowTakeAway;
    _branchId = config.branchId;
    _branchName = config.branchName;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBranches();
      _refreshKioskStatus();
      if (Platform.isWindows) _loadWindowsPrinters();
    });
  }

  @override
  void dispose() {
    _branchesRepository.dispose();
    for (final controller in [
      _restaurantName,
      _deviceId,
      _kioskId,
      _branchCode,
      _logo,
      _primaryColor,
      _idleSeconds,
      _apiKey,
      _catalogEndpoint,
      _createOrderEndpoint,
      _branchesEndpoint,
      _activationEndpoint,
      _catalogSyncMinutes,
      _orderSyncMinutes,
      _catalogVersion,
      _windowsGetnetPort,
      _windowsPrinterName,
      _newPin,
      _confirmPin,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBranches() async {
    final endpoint = Uri.tryParse(_branchesEndpoint.text.trim());
    if (endpoint == null || _apiKey.text.trim().isEmpty) {
      setState(
        () => _branchError = 'Revisa la API Key y la URL de sucursales.',
      );
      return;
    }
    setState(() {
      _loadingBranches = true;
      _branchError = null;
    });
    try {
      final branches = await _branchesRepository.load(
        apiKey: _apiKey.text.trim(),
        endpoint: endpoint,
      );
      if (!mounted) return;
      final selectedBranch = branches.firstWhere(
        (branch) => branch.id == _branchId,
        orElse: () => branches.first,
      );
      setState(() {
        _branches = branches;
        _branchId = selectedBranch.id;
        _branchName = selectedBranch.name;
        if (selectedBranch.code.trim().isNotEmpty) {
          // El identificador interno (`id`) nunca se usa como TUS.
          _branchCode.text = selectedBranch.code.trim();
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _branchError = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  String _friendlyError(Object error) {
    final text = '$error'.replaceFirst('Exception: ', '');
    return text.length > 150 ? '${text.substring(0, 150)}…' : text;
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? 'Este campo es obligatorio.'
      : null;

  String? _url(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) return requiredError;
    final uri = Uri.tryParse(value!.trim());
    return uri != null && uri.hasScheme && uri.host.isNotEmpty
        ? null
        : 'Ingresa una URL válida.';
  }

  String? _positiveNumber(String? value) {
    final number = int.tryParse(value ?? '');
    return number != null && number > 0 ? null : 'Debe ser mayor que cero.';
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_allowEatIn && !_allowTakeAway) {
      _message('Debes habilitar al menos un tipo de entrega.', error: true);
      return;
    }
    if (_branchId.trim().isEmpty) {
      _message('Selecciona una sucursal.', error: true);
      return;
    }
    final newPin = _newPin.text;
    if (newPin.isNotEmpty &&
        (newPin.length != 6 || newPin != _confirmPin.text)) {
      _message('El nuevo PIN debe tener 6 dígitos y coincidir.', error: true);
      return;
    }
    final current = ref.read(deviceConfigProvider);
    final next = current.copyWith(
      restaurantName: _restaurantName.text.trim(),
      deviceId: _deviceId.text.trim(),
      kioskId: _kioskId.text.trim(),
      branchId: _branchId,
      branchCode: _branchCode.text.trim(),
      branchName: _branchName,
      logo: _logo.text.trim(),
      primaryColor: _primaryColor.text.trim(),
      idleTimeoutSeconds: int.parse(_idleSeconds.text),
      catalogSyncMinutes: int.parse(_catalogSyncMinutes.text),
      orderSyncMinutes: int.parse(_orderSyncMinutes.text),
      catalogEndpoint: _catalogEndpoint.text.trim(),
      createOrderEndpoint: _createOrderEndpoint.text.trim(),
      branchesEndpoint: _branchesEndpoint.text.trim(),
      activationEndpoint: _activationEndpoint.text.trim(),
      apiKey: _apiKey.text.trim(),
      adminPinHash: newPin.isEmpty
          ? current.adminPinHash
          : AdminPin.hash(newPin),
      catalogVersion: _catalogVersion.text.trim(),
      paymentProvider: _paymentProvider,
      windowsGetnetPort: _windowsGetnetPort.text.trim().toUpperCase(),
      windowsPrinterName: _windowsPrinterName.text.trim(),
      paymentTerminalSide: _paymentTerminalSide,
      paymentTerminalVerticalPosition: _paymentTerminalVerticalPosition,
      operatingMode: _operatingMode,
      online: _online,
      allowEatIn: _allowEatIn,
      allowTakeAway: _allowTakeAway,
      paymentOutcome: _paymentOutcome,
      printerState: _printerState,
      dteOutcome: _dteOutcome,
    );
    setState(() => _saving = true);
    try {
      await ref.read(deviceConfigProvider.notifier).replace(next);
      _newPin.clear();
      _confirmPin.clear();
      if (mounted) _message('Configuración guardada correctamente.');
    } catch (error) {
      if (mounted) {
        _message('No se pudo guardar: ${_friendlyError(error)}', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  Future<void> _loadWindowsPrinters() async {
    setState(() => _loadingPrinters = true);
    try {
      final names = await _printerChannel.invokeListMethod<String>(
        'listPrinters',
      );
      if (mounted) setState(() => _windowsPrinters = names ?? const []);
    } on PlatformException catch (error) {
      if (mounted) {
        _message('No se pudieron listar impresoras: ${error.message}', error: true);
      }
    } finally {
      if (mounted) setState(() => _loadingPrinters = false);
    }
  }

  Future<void> _testWindowsPrinter() async {
    final name = _windowsPrinterName.text.trim();
    if (name.isEmpty) {
      _message('Selecciona una impresora antes de probar.', error: true);
      return;
    }
    setState(() => _testingPrinter = true);
    try {
      final result = await _printerChannel.invokeMapMethod<String, dynamic>(
        'printReceipt',
        {
          'printerName': name,
          'header': 'GOUR-NET',
          'orderNumber': 'PRUEBA',
          'body': 'Prueba de impresora Windows\nSin venta ni cobro\n',
          'footer': 'Comprueba que salio este papel',
        },
      );
      if (mounted) {
        _message(
          result?['message']?.toString() ?? 'Sin respuesta de la impresora.',
          error: result?['success'] != true,
        );
      }
    } on PlatformException catch (error) {
      if (mounted) _message(error.message ?? error.code, error: true);
    } finally {
      if (mounted) setState(() => _testingPrinter = false);
    }
  }

  Future<void> _refreshKioskStatus() async {
    final status = await KioskService.getStatus();
    if (mounted) setState(() => _kioskStatus = status);
  }

  Future<void> _requestExit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.logout_rounded,
          color: AppColors.error,
          size: 38,
        ),
        title: const Text('¿Salir del modo kiosco?'),
        content: const Text(
          'Android quedará disponible temporalmente para mantenimiento. '
          'Cuando vuelvas a abrir Gour-net Kiosk, el dispositivo se bloqueará '
          'automáticamente otra vez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCELAR'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('SALIR'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await KioskService.exitApp();
    } on PlatformException catch (error) {
      if (mounted) {
        _message(
          'No se pudo salir del modo kiosco: ${error.message ?? error.code}',
          error: true,
        );
      }
    } on MissingPluginException {
      if (mounted) {
        _message(
          'La salida administrativa sólo está disponible en Android.',
          error: true,
        );
      }
    }
  }

  Future<void> _requestFactoryReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.delete_forever_rounded,
          color: AppColors.error,
          size: 40,
        ),
        title: const Text('¿Restablecer de fábrica?'),
        content: const Text(
          'Se borrarán la API Key, sucursal, configuración, catálogo guardado '
          'y pedidos pendientes. El tótem volverá a la pantalla de activación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCELAR'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('BORRAR TODO'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      ref.read(sessionResetProvider)();
      context.go('/');
      await ref.read(deviceConfigProvider.notifier).factoryReset();
    } catch (error) {
      if (mounted) {
        _message(
          'No se pudo restablecer: ${_friendlyError(error)}',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 78,
          backgroundColor: AppColors.textPrimary,
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: 'Cerrar configuración',
            onPressed: _saving ? null : () => context.pop(),
            icon: const Icon(Icons.close_rounded),
          ),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configuración del tótem',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                'Acceso de administrador',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: FilledButton.icon(
                key: const Key('save-settings-button'),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'GUARDANDO' : 'GUARDAR'),
              ),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: AppColors.primary,
            indicatorWeight: 4,
            tabs: [
              Tab(icon: Icon(Icons.storefront_rounded), text: 'General'),
              Tab(icon: Icon(Icons.cloud_rounded), text: 'Integración'),
              Tab(icon: Icon(Icons.tune_rounded), text: 'Operación'),
              Tab(icon: Icon(Icons.security_rounded), text: 'Seguridad'),
            ],
          ),
        ),
        body: Form(
          key: _formKey,
          child: TabBarView(
            children: [
              _tab(children: _generalSettings()),
              _tab(children: _integrationSettings()),
              _tab(children: _operationSettings()),
              _tab(children: _securitySettings()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab({required List<Widget> children}) => ListView(
    padding: const EdgeInsets.fromLTRB(28, 28, 28, 80),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(children: children),
        ),
      ),
    ],
  );

  List<Widget> _generalSettings() => [
    _Section(
      title: 'Identidad',
      subtitle: 'Datos visibles y nombre único de este equipo.',
      icon: Icons.badge_outlined,
      child: Column(
        children: [
          _field(_restaurantName, 'Nombre del restaurante'),
          _field(_deviceId, 'Identificador del dispositivo'),
          _field(_kioskId, 'ID del tótem', hint: 'totem-001'),
          _field(_logo, 'Logo (URL o ruta)', required: false),
          _field(_primaryColor, 'Color principal', hint: '#E5187E'),
        ],
      ),
    ),
    _Section(
      title: 'Sucursal física',
      subtitle:
          'Se obtiene desde GET /sucursales usando la API Key configurada.',
      icon: Icons.location_on_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _branches.isEmpty
                    ? InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Sucursal seleccionada',
                        ),
                        child: Text('$_branchName · ID $_branchId'),
                      )
                    : DropdownButtonFormField<String>(
                        initialValue:
                            _branches.any((branch) => branch.id == _branchId)
                            ? _branchId
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Sucursal seleccionada',
                        ),
                        items: _branches
                            .map(
                              (branch) => DropdownMenuItem(
                                value: branch.id,
                                child: Text(
                                  '${branch.name} · TUS ${branch.code}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          final branch = _branches.firstWhere(
                            (item) => item.id == value,
                          );
                          setState(() {
                            _branchId = branch.id;
                            _branchName = branch.name;
                            if (branch.code.isNotEmpty) {
                              _branchCode.text = branch.code;
                            }
                          });
                        },
                      ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                height: 58,
                child: OutlinedButton.icon(
                  onPressed: _loadingBranches ? null : _loadBranches,
                  icon: _loadingBranches
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: const Text('CARGAR'),
                ),
              ),
            ],
          ),
          if (_branchError != null) ...[
            const SizedBox(height: 10),
            Text(
              _branchError!,
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 14),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'ID interno de la sucursal (referencia)',
            ),
            child: Text(
              _branchId,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 14),
          _field(
            _branchCode,
            'TUS usado en catálogo y pedidos',
            hint: '5QQTw5u1K8ed',
          ),
        ],
      ),
    ),
    _Section(
      title: 'Experiencia de compra',
      subtitle: 'Define los tipos de pedido y el tiempo de inactividad.',
      icon: Icons.touch_app_outlined,
      child: Column(
        children: [
          SwitchListTile.adaptive(
            value: _allowEatIn,
            onChanged: (value) => setState(() => _allowEatIn = value),
            title: const Text('Permitir comer en local'),
            secondary: const Icon(Icons.restaurant_rounded),
          ),
          SwitchListTile.adaptive(
            value: _allowTakeAway,
            onChanged: (value) => setState(() => _allowTakeAway = value),
            title: const Text('Permitir pedidos para llevar'),
            secondary: const Icon(Icons.shopping_bag_rounded),
          ),
          _field(
            _idleSeconds,
            'Inactividad antes de preguntar (segundos)',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: _positiveNumber,
          ),
        ],
      ),
    ),
  ];

  List<Widget> _integrationSettings() => [
    _Section(
      title: 'Credenciales',
      subtitle: 'La API Key se almacena cifrada por el sistema operativo.',
      icon: Icons.key_rounded,
      child: _field(
        _apiKey,
        'API Key',
        obscureText: !_showApiKey,
        suffixIcon: IconButton(
          onPressed: () => setState(() => _showApiKey = !_showApiKey),
          icon: Icon(
            _showApiKey
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
          ),
        ),
      ),
    ),
    _Section(
      title: 'Endpoints',
      subtitle: 'Rutas utilizadas para catálogo, pedidos y sucursales.',
      icon: Icons.route_rounded,
      child: Column(
        children: [
          _field(_catalogEndpoint, 'URL del catálogo', validator: _url),
          _field(
            _createOrderEndpoint,
            'URL para crear pedidos',
            validator: _url,
          ),
          _field(_branchesEndpoint, 'URL de sucursales', validator: _url),
          _field(
            _activationEndpoint,
            'URL de activación del tótem',
            validator: _url,
          ),
        ],
      ),
    ),
    _Section(
      title: 'Sincronización',
      subtitle: 'Frecuencia de actualización y reintentos automáticos.',
      icon: Icons.sync_rounded,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _field(
              _catalogSyncMinutes,
              'Catálogo (minutos)',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: _positiveNumber,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _field(
              _orderSyncMinutes,
              'Reintento de pedidos (minutos)',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: _positiveNumber,
            ),
          ),
        ],
      ),
    ),
    const _PaymentAuditSection(),
    const UpdateSettings(),
  ];

  List<Widget> _operationSettings() => [
    _Section(
      title: 'Modo del sistema',
      subtitle: 'Parámetros operativos y simuladores de hardware.',
      icon: Icons.settings_suggest_rounded,
      child: Column(
        children: [
          _segmented<OperatingMode>(
            value: _operatingMode,
            values: const [
              (OperatingMode.integrated, 'Integrado'),
              (OperatingMode.standalone, 'Standalone'),
            ],
            onChanged: (value) => setState(() => _operatingMode = value),
          ),
          SwitchListTile.adaptive(
            value: _online,
            onChanged: (value) => setState(() => _online = value),
            title: const Text('Conectividad habilitada'),
            secondary: const Icon(Icons.wifi_rounded),
          ),
          _field(_catalogVersion, 'Versión del catálogo'),
          const _ControlLabel('Proveedor de pago'),
          _segmented<String>(
            value: _paymentProvider,
            values: const [
              ('getnet_usb', 'Getnet USB/COM'),
              ('simulator', 'Simulador'),
            ],
            onChanged: (value) => setState(() => _paymentProvider = value),
          ),
          if (Platform.isWindows) ...[
            const SizedBox(height: 8),
            _field(
              _windowsGetnetPort,
              'Puerto COM del Getnet IM30',
              hint: 'Vacío = detección automática PAX; ejemplo COM5',
              required: false,
            ),
            _field(
              _windowsPrinterName,
              'Nombre de la impresora térmica Windows',
              hint: 'Selecciona una impresora instalada o escribe su nombre exacto',
              required: false,
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _windowsPrinters.contains(_windowsPrinterName.text)
                        ? _windowsPrinterName.text
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Impresoras instaladas en Windows',
                    ),
                    items: _windowsPrinters
                        .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                        .toList(),
                    onChanged: _windowsPrinters.isEmpty
                        ? null
                        : (name) {
                            setState(() => _windowsPrinterName.text = name ?? '');
                          },
                  ),
                ),
                IconButton(
                  tooltip: 'Actualizar impresoras',
                  onPressed: _loadingPrinters ? null : _loadWindowsPrinters,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _testingPrinter ? null : _testWindowsPrinter,
              icon: const Icon(Icons.print_rounded),
              label: const Text('Imprimir prueba'),
            ),
            const Text(
              'Guarda la configuración después de seleccionar la impresora. '
              'La prueba no inicia una venta. La impresora debe admitir ESC/POS.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    ),
    _Section(
      title: 'Diagnóstico',
      subtitle: 'Permite simular respuestas para pruebas del flujo.',
      icon: Icons.science_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ControlLabel('Resultado del pago'),
          _segmented<MockPaymentOutcome>(
            value: _paymentOutcome,
            values: const [
              (MockPaymentOutcome.approved, 'Aprobado'),
              (MockPaymentOutcome.declined, 'Rechazado'),
            ],
            onChanged: (value) => setState(() => _paymentOutcome = value),
          ),
          const _ControlLabel('Estado de impresora'),
          _segmented<MockPrinterState>(
            value: _printerState,
            values: const [
              (MockPrinterState.ready, 'Lista'),
              (MockPrinterState.noPaper, 'Sin papel'),
            ],
            onChanged: (value) => setState(() => _printerState = value),
          ),
          const _ControlLabel('Emisión DTE'),
          _segmented<MockDteOutcome>(
            value: _dteOutcome,
            values: const [
              (MockDteOutcome.success, 'Correcta'),
              (MockDteOutcome.error, 'Error'),
            ],
            onChanged: (value) => setState(() => _dteOutcome = value),
          ),
        ],
      ),
    ),
    _Section(
      title: 'Ubicación del terminal de pago',
      subtitle: 'El indicador de la pantalla apuntará hacia la posición física del POS.',
      icon: Icons.point_of_sale_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ControlLabel('Lado del tótem'),
          _segmented<PaymentTerminalSide>(
            value: _paymentTerminalSide,
            values: const [
              (PaymentTerminalSide.left, 'Izquierda'),
              (PaymentTerminalSide.right, 'Derecha'),
            ],
            onChanged: (value) => setState(() => _paymentTerminalSide = value),
          ),
          const _ControlLabel('Altura del terminal'),
          _segmented<PaymentTerminalVerticalPosition>(
            value: _paymentTerminalVerticalPosition,
            values: const [
              (PaymentTerminalVerticalPosition.center, 'Al medio'),
              (PaymentTerminalVerticalPosition.bottom, 'Abajo'),
            ],
            onChanged: (value) =>
                setState(() => _paymentTerminalVerticalPosition = value),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _securitySettings() => [
    _Section(
      title: 'Cambiar PIN de administrador',
      subtitle: 'Deja ambos campos vacíos para conservar el PIN actual. El PIN debe tener exactamente 6 dígitos.',
      icon: Icons.pin_rounded,
      child: Column(
        children: [
          _field(
            _newPin,
            'Nuevo PIN',
            required: false,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
          ),
          _field(
            _confirmPin,
            'Confirmar nuevo PIN',
            required: false,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
          ),
        ],
      ),
    ),
    _Section(
      title: 'Modo kiosco del dispositivo',
      subtitle: 'Impide abrir otras aplicaciones, Inicio, recientes, ajustes y notificaciones.',
      icon: Icons.phonelink_lock_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_kioskStatus == null)
            const Center(child: CircularProgressIndicator())
          else if (Platform.isWindows) ...[
            _KioskStateRow(
              label: 'Pantalla completa',
              active: _kioskStatus!.locked,
            ),
            const Text(
              'El bloqueo del sistema Windows requiere configurar Shell Launcher con una cuenta de kiosco en Windows Enterprise, Education o IoT Enterprise. La pantalla completa por sí sola no bloquea Ctrl+Alt+Supr.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ] else ...[
            _KioskStateRow(
              label: 'Administrador del dispositivo',
              active: _kioskStatus!.deviceOwner,
            ),
            _KioskStateRow(
              label: 'Aplicación autorizada',
              active: _kioskStatus!.lockTaskPermitted,
            ),
            _KioskStateRow(
              label: 'Bloqueo activo',
              active: _kioskStatus!.locked,
            ),
          ],
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _refreshKioskStatus,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('ACTUALIZAR ESTADO'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('exit-kiosk-button'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size.fromHeight(58),
            ),
            onPressed: _requestExit,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('SALIR DE LA APP'),
          ),
          const SizedBox(height: 10),
          const Text(
            'Sólo para mantenimiento. La app volverá a bloquear el equipo al abrirse.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
    _Section(
      title: 'Restablecimiento de fábrica',
      subtitle: 'Borra todos los datos locales y exige una nueva activación.',
      icon: Icons.restart_alt_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'También elimina la copia local del catálogo y cualquier pedido pendiente de sincronización.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('factory-reset-button'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
            ),
            onPressed: _saving ? null : _requestFactoryReset,
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('RESTABLECER DE FÁBRICA'),
          ),
        ],
      ),
    ),
    const _SecurityNotice(),
  ];

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool required = true,
    bool obscureText = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator ?? (required ? _required : null),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffixIcon,
      ),
    ),
  );

  Widget _segmented<T>({
    required T value,
    required List<(T, String)> values,
    required ValueChanged<T> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        segments: values
            .map(
              (item) => ButtonSegment<T>(value: item.$1, label: Text(item.$2)),
            )
            .toList(),
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFFFE6F2),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        child,
      ],
    ),
  );
}

class _ControlLabel extends StatelessWidget {
  const _ControlLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 10),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
  );
}

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF7F1),
      borderRadius: BorderRadius.circular(22),
    ),
    child: const Row(
      children: [
        Icon(Icons.verified_user_rounded, color: AppColors.success, size: 34),
        SizedBox(width: 14),
        Expanded(
          child: Text(
            'La API Key y el PIN no se guardan en el archivo normal de preferencias. El acceso se cierra al salir de esta pantalla.',
            style: TextStyle(fontWeight: FontWeight.w700, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _KioskStateRow extends StatelessWidget {
  const _KioskStateRow({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(
          active ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: active ? AppColors.success : AppColors.error,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          active ? 'ACTIVO' : 'INACTIVO',
          style: TextStyle(
            color: active ? AppColors.success : AppColors.error,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _PaymentAuditSection extends ConsumerStatefulWidget {
  const _PaymentAuditSection();

  @override
  ConsumerState<_PaymentAuditSection> createState() =>
      _PaymentAuditSectionState();
}

class _PaymentAuditSectionState extends ConsumerState<_PaymentAuditSection> {
  late Future<List<Map<String, dynamic>>> _entries;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _entries = ref.read(paymentAuditRepositoryProvider).readAll();
  }

  Future<void> _resolve(
    Map<String, dynamic> entry, {
    required bool paymentConfirmed,
  }) async {
    final orderNumber = entry['orderNumber'];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          paymentConfirmed ? '¿Cobro confirmado?' : '¿Confirmar que no cobró?',
        ),
        content: Text(
          paymentConfirmed
              ? 'Usa esta opción sólo después de comprobar en Getnet que el pedido #$orderNumber fue cobrado. El pedido deberá revisarse manualmente.'
              : 'Usa esta opción sólo después de comprobar en Getnet que el pedido #$orderNumber no produjo ningún cobro. Esto habilitará nuevas ventas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('VOLVER'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('CONFIRMAR'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(paymentAuditRepositoryProvider)
        .resolveManually(
          entry['entryId'].toString(),
          paymentConfirmed: paymentConfirmed,
        );
    if (mounted) setState(_reload);
  }

  bool _isUnresolved(String status) => const {
    'processing',
    'cancellationRequested',
    'uncertain',
  }.contains(status);

  String _statusLabel(String status) => switch (status) {
    'processing' => 'EN PROCESO',
    'cancellationRequested' => 'CANCELACIÓN SOLICITADA',
    'approved' => 'APROBADO',
    'declined' => 'RECHAZADO / SIN COBRO',
    'cancelled' => 'CANCELADO',
    'uncertain' => 'POR CONCILIAR',
    _ => status.toUpperCase(),
  };

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Conciliación Getnet',
    subtitle: 'Historial local de intentos y resolución controlada de resultados inciertos.',
    icon: Icons.receipt_long_rounded,
    child: FutureBuilder<List<Map<String, dynamic>>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Text(
            'No se pudo leer el registro local de conciliación.',
            style: TextStyle(color: AppColors.error),
          );
        }
        final entries = snapshot.data ?? const [];
        if (entries.isEmpty) {
          return const Text('Todavía no hay transacciones registradas.');
        }
        final approved = entries
            .where((entry) => entry['status'] == 'approved')
            .length;
        final unresolved = entries
            .where((entry) => _isUnresolved('${entry['status']}'))
            .length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                Text('${entries.length} intentos'),
                Text('$approved aprobados'),
                Text(
                  '$unresolved por conciliar',
                  style: TextStyle(
                    color: unresolved > 0 ? AppColors.error : AppColors.success,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final entry in entries.take(10)) ...[
              const Divider(),
              Text(
                'Pedido #${entry['orderNumber']} · ${formatClp((entry['amount'] as num?)?.toInt() ?? 0)}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                _statusLabel('${entry['status']}'),
                style: TextStyle(
                  color: _isUnresolved('${entry['status']}')
                      ? AppColors.error
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if ((entry['getnet'] as Map?)?['operationId']
                      ?.toString()
                      .isNotEmpty ==
                  true)
                Text('Operación ${(entry['getnet'] as Map)['operationId']}'),
              Text(
                '${entry['startedAt'] ?? ''}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (_isUnresolved('${entry['status']}')) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => _resolve(entry, paymentConfirmed: false),
                      child: const Text('CONFIRMAR SIN COBRO'),
                    ),
                    FilledButton(
                      onPressed: () => _resolve(entry, paymentConfirmed: true),
                      child: const Text('COBRO CONFIRMADO'),
                    ),
                  ],
                ),
              ],
            ],
          ],
        );
      },
    ),
  );
}
