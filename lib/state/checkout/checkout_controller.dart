import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/payment_audit_repository.dart';
import '../../domain/models/order.dart';
import '../app_providers.dart';
import '../cart/cart_controller.dart';
import '../device_config_controller.dart';
import '../session/session_controller.dart';

enum CheckoutStage {
  idle,
  waitingForCard,
  processing,
  cancelling,
  approved,
  declined,
  uncertain,
}

class CheckoutState {
  const CheckoutState({
    this.stage = CheckoutStage.idle,
    this.order,
    this.message,
  });
  final CheckoutStage stage;
  final Order? order;
  final String? message;
}

class CheckoutController extends StateNotifier<CheckoutState> {
  CheckoutController(this.ref) : super(const CheckoutState());
  final Ref ref;
  String? _transactionId;
  int? _orderNumber;
  String? _auditEntryId;
  bool _starting = false;

  Future<void> start() async {
    if (_starting) return;
    if (state.stage == CheckoutStage.waitingForCard ||
        state.stage == CheckoutStage.processing ||
        state.stage == CheckoutStage.cancelling ||
        state.stage == CheckoutStage.approved ||
        state.stage == CheckoutStage.uncertain) {
      return;
    }
    final items = ref.read(cartProvider);
    if (items.isEmpty) return;
    _starting = true;
    try {
      final uuid = _transactionId ??= const Uuid().v4();
      final orderNumber = _orderNumber ??= await ref
          .read(deviceConfigProvider.notifier)
          .reserveOrderNumber();
      final amount = ref.read(cartTotalProvider);
      final audit = await _beginAudit(
        transactionId: uuid,
        orderNumber: orderNumber,
        amount: amount,
      );
      if (audit == null) return;
      if (!audit.allowed || audit.entryId == null) {
        state = CheckoutState(
          stage: CheckoutStage.uncertain,
          message: audit.message,
        );
        return;
      }
      _auditEntryId = audit.entryId;
      state = const CheckoutState(stage: CheckoutStage.waitingForCard);
      state = const CheckoutState(stage: CheckoutStage.processing);
      final result = await ref
          .read(paymentGatewayProvider)
          .pay(amount: amount, transactionId: uuid, ticketNumber: orderNumber);
      try {
        await ref
            .read(paymentAuditRepositoryProvider)
            .complete(audit.entryId!, result);
      } catch (_) {
        if (!result.approved) {
          state = const CheckoutState(
            stage: CheckoutStage.uncertain,
            message: 'No se pudo guardar el resultado del pago. No vuelvas a intentarlo y solicita asistencia.',
          );
          return;
        }
      }
      if (!result.approved) {
        state = CheckoutState(
          stage: result.outcomeCertain
              ? CheckoutStage.declined
              : CheckoutStage.uncertain,
          message: result.message,
        );
        return;
      }
      final order = Order(
        uuid: uuid,
        number: orderNumber,
        type: ref.read(sessionProvider).orderType ?? OrderType.eatIn,
        items: List.unmodifiable(items),
        paymentStatus: PaymentStatus.approved,
        dteStatus: DteStatus.pending,
        syncStatus: SyncStatus.pending,
        createdAt: DateTime.now(),
        paymentReference: result.authorizationCode,
        getnetTransaction: result.getnetTransaction,
        status: SaleStatus.paymentApproved,
      );
      await ref.read(orderRepositoryProvider).save(order);
      state = CheckoutState(stage: CheckoutStage.approved, order: order);
    } finally {
      _starting = false;
    }
  }

  Future<PaymentAuditBeginResult?> _beginAudit({
    required String transactionId,
    required int orderNumber,
    required int amount,
  }) async {
    try {
      return await ref
          .read(paymentAuditRepositoryProvider)
          .begin(
            transactionId: transactionId,
            orderNumber: orderNumber,
            amount: amount,
          );
    } catch (_) {
      state = const CheckoutState(
        stage: CheckoutStage.uncertain,
        message: 'No se pudo crear el registro de conciliación. El pago no fue iniciado; solicita asistencia.',
      );
      return null;
    }
  }

  Future<bool> cancelPayment() async {
    if (state.stage != CheckoutStage.processing &&
        state.stage != CheckoutStage.waitingForCard) {
      return false;
    }
    state = const CheckoutState(stage: CheckoutStage.cancelling);
    final entryId = _auditEntryId;
    if (entryId != null) {
      try {
        await ref
            .read(paymentAuditRepositoryProvider)
            .markCancellationRequested(entryId);
      } catch (_) {
        // La cancelación sigue siendo prioritaria; el intento original ya
        // quedó registrado antes de enviar el cobro al POS.
      }
    }
    final result = await ref.read(paymentGatewayProvider).cancelActivePayment();
    if (!result.accepted && state.stage == CheckoutStage.cancelling) {
      state = CheckoutState(
        stage: CheckoutStage.processing,
        message: result.message,
      );
    }
    return result.accepted;
  }

  void reset() {
    _transactionId = null;
    _orderNumber = null;
    _auditEntryId = null;
    _starting = false;
    state = const CheckoutState();
  }
}

final checkoutProvider =
    StateNotifierProvider<CheckoutController, CheckoutState>(
      (ref) => CheckoutController(ref),
    );
