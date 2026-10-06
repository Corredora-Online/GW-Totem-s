import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/gournet_api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../data/remote/gournet_activation_repository.dart';
import '../../data/remote/gournet_branches_repository.dart';
import '../../domain/models/branch.dart';
import '../../state/device_config_controller.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _pollInterval = Duration(seconds: 10);
  static const _codeLifetime = Duration(minutes: 5);
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  late final GournetActivationRepository _activationRepository;
  late final GournetBranchesRepository _branchesRepository;
  Timer? _countdownTimer;
  Timer? _pollTimer;
  String _token = '';
  DateTime? _expiresAt;
  Duration _remaining = _codeLifetime;
  bool _expired = false;
  bool _polling = false;
  bool _validating = false;
  bool _validationFailed = false;
  bool _savingBranch = false;
  String _pendingApiKey = '';
  String _status = 'Esperando activación de soporte…';
  List<Branch> _branches = const [];
  Branch? _selectedBranch;

  @override
  void initState() {
    super.initState();
    final config = ref.read(deviceConfigProvider);
    _activationRepository = GournetActivationRepository(
      endpoint:
          Uri.tryParse(config.activationEndpoint.trim()) ??
          GournetApiConfig.activationUri,
    );
    _branchesRepository = GournetBranchesRepository();
    if (config.apiKey.trim().isNotEmpty) {
      _pendingApiKey = config.apiKey.trim();
      _validating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_validateApiKey(_pendingApiKey));
      });
    } else {
      _startNewCode(notify: false);
    }
  }

  @override
  void dispose() {
    _stopTimers();
    _activationRepository.dispose();
    _branchesRepository.dispose();
    super.dispose();
  }

  void _startNewCode({bool notify = true}) {
    _stopTimers();
    final random = Random.secure();
    final token = List.generate(
      8,
      (_) => _alphabet[random.nextInt(_alphabet.length)],
    ).join();
    final expiresAt = DateTime.now().add(_codeLifetime);

    void updateState() {
      _token = token;
      _expiresAt = expiresAt;
      _remaining = _codeLifetime;
      _expired = false;
      _polling = false;
      _validating = false;
      _validationFailed = false;
      _pendingApiKey = '';
      _branches = const [];
      _selectedBranch = null;
      _status = 'Esperando activación de soporte…';
    }

    if (notify) {
      setState(updateState);
    } else {
      updateState();
    }
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickCountdown(token),
    );
    _pollTimer = Timer.periodic(
      _pollInterval,
      (_) => unawaited(_pollActivation(token)),
    );
  }

  void _tickCountdown(String token) {
    if (!mounted || token != _token || _expiresAt == null) return;
    final remaining = _expiresAt!.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _expireCode(token);
      return;
    }
    setState(() => _remaining = remaining);
  }

  void _expireCode(String token) {
    if (!mounted || token != _token || _expired) return;
    _stopTimers();
    setState(() {
      _remaining = Duration.zero;
      _expired = true;
      _polling = false;
      _status = 'Este código venció y ya no se consultará.';
    });
  }

  Future<void> _pollActivation(String token) async {
    if (!mounted || _expired || _polling || token != _token) return;
    final expiresAt = _expiresAt;
    if (expiresAt == null || !DateTime.now().isBefore(expiresAt)) {
      _expireCode(token);
      return;
    }
    setState(() {
      _polling = true;
      _status = 'Consultando activación…';
    });
    try {
      final apiKey = await _activationRepository.check(token);
      if (!mounted || token != _token || _expired) return;
      if (!DateTime.now().isBefore(expiresAt)) {
        _expireCode(token);
        return;
      }
      if (apiKey == null) {
        setState(() => _status = 'Esperando activación de soporte…');
        return;
      }
      final config = ref.read(deviceConfigProvider);
      await ref
          .read(deviceConfigProvider.notifier)
          .replace(
            config.copyWith(
              apiKey: apiKey,
              branchId: '',
              branchCode: '',
              branchName: '',
            ),
          );
      _stopTimers();
      await _validateApiKey(apiKey);
    } catch (_) {
      if (!mounted || token != _token || _expired) return;
      setState(() {
        _status = 'Sin conexión. Se reintentará automáticamente.';
      });
    } finally {
      if (mounted && token == _token && !_expired && !_validating) {
        setState(() => _polling = false);
      }
    }
  }

  Future<void> _validateApiKey(String apiKey) async {
    if (!mounted) return;
    setState(() {
      _validating = true;
      _validationFailed = false;
      _pendingApiKey = apiKey;
      _polling = false;
      _status = 'Activación recibida. Validando cuenta…';
    });
    final config = ref.read(deviceConfigProvider);
    final endpoint = Uri.tryParse(config.branchesEndpoint.trim());
    try {
      if (endpoint == null) {
        throw const FormatException('La URL de sucursales no es válida.');
      }
      final loaded = await _branchesRepository.load(
        apiKey: apiKey,
        endpoint: endpoint,
      );
      final validBranches = loaded
          .where((branch) => branch.code.trim().isNotEmpty)
          .toList(growable: false);
      if (validBranches.isEmpty) {
        throw const FormatException('Las sucursales no tienen TUS válido.');
      }
      if (!mounted) return;
      setState(() {
        _branches = validBranches;
        _selectedBranch = validBranches.length == 1
            ? validBranches.single
            : null;
        _validating = false;
        _status = 'Cuenta activada. Selecciona la sucursal del tótem.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _validating = false;
        _validationFailed = true;
        _remaining = Duration.zero;
        _status = 'No se pudo validar la cuenta ni cargar sus sucursales.';
      });
    }
  }

  Future<void> _discardActivation() async {
    if (_validating) return;
    setState(() => _validating = true);
    try {
      final config = ref.read(deviceConfigProvider);
      await ref
          .read(deviceConfigProvider.notifier)
          .replace(
            config.copyWith(
              apiKey: '',
              branchId: '',
              branchCode: '',
              branchName: '',
            ),
          );
      if (mounted) _startNewCode();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _validating = false;
        _validationFailed = true;
        _status = 'No fue posible descartar la credencial guardada.';
      });
    }
  }

  Future<void> _saveBranch() async {
    final branch = _selectedBranch;
    if (branch == null || _savingBranch) return;
    setState(() => _savingBranch = true);
    try {
      final config = ref.read(deviceConfigProvider);
      await ref
          .read(deviceConfigProvider.notifier)
          .replace(
            config.copyWith(
              branchId: branch.id,
              branchCode: branch.code.trim(),
              branchName: branch.name,
            ),
          );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingBranch = false;
        _status = 'No fue posible guardar la sucursal. Intenta nuevamente.';
      });
    }
  }

  void _stopTimers() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    _countdownTimer = null;
    _pollTimer = null;
  }

  String get _formattedRemaining {
    final totalSeconds = _remaining.inSeconds.clamp(0, 5999);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _token));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Código copiado')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    _branches.isEmpty ? 'Activa tu tótem' : 'Elige tu sucursal',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _branches.isNotEmpty
                        ? _branchStep()
                        : _activationStep(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _activationStep() {
    if (_validating) {
      return Padding(
        key: const ValueKey('validating-activation'),
        padding: const EdgeInsets.only(top: 72),
        child: Column(
          children: [
            const SizedBox(
              width: 54,
              height: 54,
              child: CircularProgressIndicator(strokeWidth: 5),
            ),
            const SizedBox(height: 28),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      );
    }
    if (_validationFailed) {
      return Padding(
        key: const ValueKey('activation-validation-failed'),
        padding: const EdgeInsets.only(top: 46),
        child: Column(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: AppColors.error,
              size: 64,
            ),
            const SizedBox(height: 22),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'La API Key permanece guardada de forma segura. Puedes reintentar sin pedir otro código a soporte.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              key: const Key('retry-api-key-validation'),
              onPressed: () => _validateApiKey(_pendingApiKey),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('REINTENTAR VALIDACIÓN'),
            ),
            const SizedBox(height: 14),
            TextButton(
              key: const Key('request-new-activation'),
              onPressed: _discardActivation,
              child: const Text('SOLICITAR UN CÓDIGO NUEVO'),
            ),
          ],
        ),
      );
    }
    return Column(
      key: const ValueKey('activation-code-step'),
      children: [
        Text(
          'Comparte este código con soporte Gour-net.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 34),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(32, 38, 32, 30),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.large),
            border: Border.all(color: AppColors.border, width: 2),
          ),
          child: Column(
            children: [
              SelectableText(
                _token,
                key: const Key('support-activation-code'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 54,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: _expired ? null : _copyCode,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('COPIAR CÓDIGO'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          decoration: BoxDecoration(
            color: _expired
                ? AppColors.error.withValues(alpha: 0.08)
                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _expired ? Icons.timer_off_rounded : Icons.timer_outlined,
                color: _expired
                    ? AppColors.error
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                _formattedRemaining,
                key: const Key('activation-countdown'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_polling) const LinearProgressIndicator(minHeight: 3),
        if (_polling) const SizedBox(height: 14),
        Text(
          _status,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: _expired ? AppColors.error : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'El tótem consulta de forma segura cada ${_pollInterval.inSeconds} segundos.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_expired) ...[
          const SizedBox(height: 28),
          ElevatedButton.icon(
            key: const Key('renew-activation-code'),
            onPressed: _startNewCode,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('GENERAR NUEVO CÓDIGO'),
          ),
        ],
      ],
    );
  }

  Widget _branchStep() {
    return Column(
      key: const ValueKey('branch-step'),
      children: [
        Text(
          'Selecciona el local donde está instalado físicamente este tótem. El TUS de esta sucursal se usará para el catálogo y los pedidos.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 36),
        DropdownButtonFormField<Branch>(
          key: const Key('onboarding-branch'),
          initialValue: _selectedBranch,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Sucursal',
            prefixIcon: Icon(Icons.store_mall_directory_outlined),
          ),
          items: _branches
              .map(
                (branch) => DropdownMenuItem(
                  value: branch,
                  child: Text(
                    branch.subtitle.isEmpty
                        ? branch.name
                        : '${branch.name} · ${branch.subtitle}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: _savingBranch
              ? null
              : (value) => setState(() => _selectedBranch = value),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            key: const Key('save-onboarding-branch'),
            onPressed: _selectedBranch == null || _savingBranch
                ? null
                : _saveBranch,
            icon: _savingBranch
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline_rounded),
            label: Text(_savingBranch ? 'GUARDANDO…' : 'CONFIRMAR SUCURSAL'),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _status,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
