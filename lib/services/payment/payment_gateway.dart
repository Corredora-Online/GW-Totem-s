import '../../domain/models/order.dart';

class PaymentResult {
  const PaymentResult({
    required this.approved,
    required this.authorizationCode,
    this.message,
    this.getnetTransaction,
    this.outcomeCertain = true,
    this.cancelled = false,
  });
  final bool approved;
  final String authorizationCode;
  final String? message;
  final GetnetTransactionData? getnetTransaction;

  /// `false` cuando la solicitud salió hacia el POS pero no llegó una
  /// respuesta final verificable. En ese caso no es seguro volver a cobrar.
  final bool outcomeCertain;
  final bool cancelled;
}

class PaymentCancellationResult {
  const PaymentCancellationResult({required this.accepted, this.message});

  final bool accepted;
  final String? message;
}

abstract interface class PaymentGateway {
  Future<PaymentResult> pay({
    required int amount,
    required String transactionId,
    required int ticketNumber,
  });

  /// Solicita al POS cancelar únicamente la venta que está en curso.
  Future<PaymentCancellationResult> cancelActivePayment();
}
