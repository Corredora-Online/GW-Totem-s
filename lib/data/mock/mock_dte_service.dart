import '../../domain/models/order.dart';
import '../../services/dte/dte_service.dart';

class MockDteService implements DteService {
  const MockDteService({required this.shouldSucceed});
  final bool shouldSucceed;

  @override
  Future<DteResult> emit({required Order order}) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return DteResult(
      success: shouldSucceed,
      folio: shouldSucceed ? 104 : null,
      message: shouldSucceed ? null : 'Error DTE simulado',
    );
  }
}
