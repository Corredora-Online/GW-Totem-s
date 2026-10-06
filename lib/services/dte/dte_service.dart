import '../../domain/models/order.dart';

class DteResult {
  const DteResult({required this.success, this.folio, this.message});
  final bool success;
  final int? folio;
  final String? message;
}

abstract interface class DteService {
  Future<DteResult> emit({required Order order});
}
