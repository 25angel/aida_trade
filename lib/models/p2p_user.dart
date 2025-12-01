class P2PUser {
  final String nickname;
  final int timeLimitMinutes;
  final String orderLimits;
  final double rateKZT;
  final int availableUSDT;
  final String paymentMethods;
  final int ordersCount;
  final int completionRatePercent;
  final String? traderInitial;
  final bool? hasStar;

  P2PUser({
    required this.nickname,
    required this.timeLimitMinutes,
    required this.orderLimits,
    required this.rateKZT,
    required this.availableUSDT,
    required this.paymentMethods,
    required this.ordersCount,
    required this.completionRatePercent,
    this.traderInitial,
    this.hasStar,
  });
}
