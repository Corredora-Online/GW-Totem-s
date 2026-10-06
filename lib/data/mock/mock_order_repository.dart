import '../../domain/models/order.dart';
import '../../domain/repositories/order_repository.dart';

class MockOrderRepository implements OrderRepository {
  final List<Order> orders = [];

  @override
  Future<void> save(Order order) async => orders.add(order);

  @override
  Future<void> syncPending() async {}
}
