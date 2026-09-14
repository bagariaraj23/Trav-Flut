const unsettledBalanceLeaveMessage =
    'Settle your trip expenses before leaving. Open Money on the trip thread to see who still owes whom.';

const unsettledBalanceKickMessage =
    'This person still has an unpaid trip balance. Settle expenses first.';

bool isUnsettledBalancePayload(Object? data) {
  if (data is! Map) return false;
  if (data['code'] == 'UNSETTLED_BALANCE') return true;
  final meta = data['meta'];
  return meta is Map && meta['code'] == 'UNSETTLED_BALANCE';
}

String leaveErrorFrom(Object? data, String fallback) {
  if (isUnsettledBalancePayload(data)) return unsettledBalanceLeaveMessage;
  if (data is Map && data['error'] is String) {
    final error = data['error'] as String;
    if (error.isNotEmpty) return error;
  }
  return fallback;
}

String kickErrorFrom(Object? data, String fallback) {
  if (isUnsettledBalancePayload(data)) return unsettledBalanceKickMessage;
  if (data is Map && data['error'] is String) {
    final error = data['error'] as String;
    if (error.isNotEmpty) return error;
  }
  return fallback;
}
