/// 금액을 천단위 콤마와 '원'을 붙여 표시한다. 발주 화면 전반에서 같은 표기를 쓰기 위한 공통 함수.
String formatWon(int amount) {
  return '${formatNumber(amount)}원';
}

/// 목록에서 쓰는 짧은 시각 표기. 오늘이면 시:분, 어제면 '어제', 그 외에는 월.일.
/// 발주는 대부분 당일·최근 건을 보므로 최근일수록 정밀하게 보여준다.
String formatListTime(DateTime? time) {
  if (time == null) return '';
  final DateTime now = DateTime.now();
  final DateTime day = DateTime(time.year, time.month, time.day);
  final DateTime today = DateTime(now.year, now.month, now.day);
  final int diff = today.difference(day).inDays;
  if (diff == 0) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
  if (diff == 1) return '어제';
  return '${time.month}.${time.day}';
}

/// 천단위 콤마만 적용한다 (단위 없이 수량 등에 사용).
String formatNumber(int value) {
  final String digits = value.abs().toString();
  final StringBuffer buf = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return value < 0 ? '-$buf' : buf.toString();
}
