/// 签到的「当天」判定。
///
/// 服务端按自然日重置，客户端缓存也只能认日期：过了零点就该重新签，
/// 而不是从上次签到起算 24 小时。
String signInDayKey(DateTime time) {
  final y = time.year.toString().padLeft(4, '0');
  final m = time.month.toString().padLeft(2, '0');
  final d = time.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// 本地记录的签到日期是否就是今天。
bool signedInOn(String? savedDay, DateTime now) => savedDay != null && savedDay == signInDayKey(now);
