import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/order.dart';

class SessionState {
  const SessionState({this.orderType});
  final OrderType? orderType;
  SessionState copyWith({OrderType? orderType}) =>
      SessionState(orderType: orderType ?? this.orderType);
}

class SessionController extends StateNotifier<SessionState> {
  SessionController() : super(const SessionState());
  void setOrderType(OrderType type) => state = SessionState(orderType: type);
  void reset() => state = const SessionState();
}

final sessionProvider = StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(),
);
