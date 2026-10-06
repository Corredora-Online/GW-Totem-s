import '../../services/payment/payment_gateway.dart';

class MockGetnetGateway implements PaymentGateway {
  const MockGetnetGateway({required this.shouldApprove});
  final bool shouldApprove;

  @override
  Future<PaymentCancellationResult> cancelActivePayment() async =>
      const PaymentCancellationResult(
        accepted: true,
        message: 'Cancelación simulada enviada.',
      );

  @override
  Future<PaymentResult> pay({
    required int amount,
    required String transactionId,
    required int ticketNumber,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final numericReference = transactionId.codeUnits
        .fold<int>(0, (value, unit) => (value * 31 + unit) % 100000000)
        .toString()
        .padLeft(8, '0');
    return PaymentResult(
      approved: shouldApprove,
      authorizationCode: shouldApprove ? numericReference : '',
      message: shouldApprove
          ? null
          : 'La tarjeta fue rechazada por el simulador.',
    );
  }
}
