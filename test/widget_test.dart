import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/waf_solver.dart';

void main() {
  test('WAF 求解器能识别挑战页并生成 40 位 Cookie 值', () {
    const arg1 = '0123456789abcdef0123456789abcdef01234567';
    final html = "<script>var arg1='$arg1';</script>";

    expect(WafSolver.isChallenge(html), isTrue);

    final solved = WafSolver.solveFromHtml(html);
    expect(solved, isNotNull);
    expect(solved!.length, arg1.length);
    expect(RegExp(r'^[0-9a-f]{40}$').hasMatch(solved), isTrue);
  });
}
