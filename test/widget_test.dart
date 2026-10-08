import 'package:flutter_test/flutter_test.dart';

import 'package:haven/util.dart';

void main() {
  test('fmtDur formats durations', () {
    expect(fmtDur(65), '1:05');
    expect(fmtDur(3700), '1:01:40');
    expect(fmtDur(0), '0:00');
  });

  test('fmtTotal formats totals', () {
    expect(fmtTotal(3600), '1小时');
    expect(fmtTotal(3900), '1小时5分');
    expect(fmtTotal(90), '1分钟');
  });

  test('cleanHtml strips tags', () {
    expect(cleanHtml('<p>你好<br/>世界</p>'), '你好\n世界');
  });
}
