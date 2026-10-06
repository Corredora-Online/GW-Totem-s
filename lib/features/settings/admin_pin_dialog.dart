import 'package:flutter/material.dart';

import '../../core/security/admin_pin.dart';
import '../../core/theme/app_colors.dart';

DateTime? _adminAccessLockedUntil;

Future<bool> showAdminPinDialog(
  BuildContext context, {
  required String expectedHash,
}) async {
  final lockedUntil = _adminAccessLockedUntil;
  if (lockedUntil != null && lockedUntil.isAfter(DateTime.now())) {
    final seconds = lockedUntil.difference(DateTime.now()).inSeconds + 1;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Acceso bloqueado. Intenta en $seconds segundos.'),
      ),
    );
    return false;
  }
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _AdminPinDialog(expectedHash: expectedHash),
      ) ??
      false;
}

class _AdminPinDialog extends StatefulWidget {
  const _AdminPinDialog({required this.expectedHash});

  final String expectedHash;

  @override
  State<_AdminPinDialog> createState() => _AdminPinDialogState();
}

class _AdminPinDialogState extends State<_AdminPinDialog> {
  String _pin = '';
  String? _error;
  int _failedAttempts = 0;

  void _digit(int value) {
    if (_pin.length >= 6) return;
    setState(() {
      _error = null;
      _pin += value.toString();
    });
    if (_pin.length == 6) _verify();
  }

  void _verify() {
    if (AdminPin.isValid(_pin, widget.expectedHash)) {
      Navigator.of(context).pop(true);
      return;
    }
    _failedAttempts++;
    if (_failedAttempts >= 3) {
      _adminAccessLockedUntil = DateTime.now().add(const Duration(seconds: 30));
      Navigator.of(context).pop(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acceso bloqueado durante 30 segundos.')),
      );
      return;
    }
    setState(() {
      _pin = '';
      _error = 'PIN incorrecto. Quedan ${3 - _failedAttempts} intentos.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 70, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 34,
                backgroundColor: Color(0xFFFFE6F2),
                child: Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 38,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Acceso de administración',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ingresa el PIN de 6 dígitos',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  6,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 17,
                    height: 17,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index < _pin.length
                          ? AppColors.primary
                          : AppColors.border,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 38,
                child: _error == null
                    ? null
                    : Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                childAspectRatio: 1.7,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final digit in const [1, 2, 3, 4, 5, 6, 7, 8, 9])
                    _PinKey(label: '$digit', onTap: () => _digit(digit)),
                  _PinKey(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  _PinKey(label: '0', onTap: () => _digit(0)),
                  _PinKey(
                    icon: Icons.backspace_outlined,
                    onTap: _pin.isEmpty
                        ? null
                        : () => setState(
                            () => _pin = _pin.substring(0, _pin.length - 1),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinKey extends StatelessWidget {
  const _PinKey({this.label, this.icon, this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: onTap == null ? AppColors.background : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppColors.border),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Center(
        child: icon != null
            ? Icon(icon, size: 25)
            : Text(
                label!,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
      ),
    ),
  );
}
