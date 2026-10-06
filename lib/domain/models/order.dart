import 'cart_item.dart';

enum OrderType { eatIn, takeAway }

enum PaymentStatus { pending, approved, declined }

enum DteStatus { pending, emitted, error }

enum SyncStatus { pending, synced }

enum SaleStatus {
  draft,
  paymentPending,
  paymentApproved,
  dtePending,
  dteEmitted,
  orderPendingSync,
  synced,
  completed,
}

class GetnetTransactionData {
  const GetnetTransactionData({
    required this.responseCode,
    required this.responseMessage,
    required this.commerceCode,
    required this.terminalId,
    required this.ticket,
    required this.authorizationCode,
    required this.operationId,
    required this.amount,
    required this.cardBrand,
    required this.cardType,
    required this.last4Digits,
    required this.transactionDate,
  });

  final int responseCode;
  final String responseMessage;
  final String commerceCode;
  final String terminalId;
  final String ticket;
  final String authorizationCode;
  final String operationId;
  final int amount;
  final String cardBrand;
  final String cardType;
  final String last4Digits;
  final String transactionDate;
}

class Order {
  const Order({
    required this.uuid,
    required this.number,
    required this.type,
    required this.items,
    required this.paymentStatus,
    required this.dteStatus,
    required this.syncStatus,
    required this.createdAt,
    required this.paymentReference,
    this.getnetTransaction,
    this.status = SaleStatus.draft,
  });

  final String uuid;
  final int number;
  final OrderType type;
  final List<CartItem> items;
  final PaymentStatus paymentStatus;
  final DteStatus dteStatus;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final String paymentReference;
  final GetnetTransactionData? getnetTransaction;
  final SaleStatus status;

  int get subtotal => items.fold(0, (sum, item) => sum + item.total);
  int get total => subtotal;

  Order copyWith({
    PaymentStatus? paymentStatus,
    DteStatus? dteStatus,
    SyncStatus? syncStatus,
    SaleStatus? status,
  }) => Order(
    uuid: uuid,
    number: number,
    type: type,
    items: items,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    dteStatus: dteStatus ?? this.dteStatus,
    syncStatus: syncStatus ?? this.syncStatus,
    createdAt: createdAt,
    paymentReference: paymentReference,
    getnetTransaction: getnetTransaction,
    status: status ?? this.status,
  );
}
