import '../../domain/models/order.dart';
import '../../services/printer/printer_service.dart';

class MockPrinterService implements PrinterService {
  const MockPrinterService({required this.hasPaper});
  final bool hasPaper;

  @override
  Future<PrintResult> print(Order order) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return PrintResult(
      success: hasPaper,
      message: hasPaper ? null : 'Impresora sin papel',
    );
  }
}
