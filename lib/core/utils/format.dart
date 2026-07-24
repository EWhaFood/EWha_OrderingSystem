/// 금액을 천단위 콤마와 '원'을 붙여 표시한다. 발주 화면 전반에서 같은 표기를 쓰기 위한 공통 함수.
String formatWon(int amount) {
  return '${formatNumber(amount)}원';
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
