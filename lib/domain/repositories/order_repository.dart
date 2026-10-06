import '../models/order.dart';

abstract interface class OrderRepository {
  Future<void> save(Order order);

  Future<void> syncPending();
}
