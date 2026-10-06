import '../../domain/models/order.dart';

class PrintResult {
  const PrintResult({required this.success, this.message});
  final bool success;
  final String? message;
}

abstract interface class PrinterService {
  Future<PrintResult> print(Order order);
}
