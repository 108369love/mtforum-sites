import 'dart:convert';

/// 站点前置 WAF（Aliyun acw_sc__v2）的本地求解。
///
/// 页面返回一段混淆脚本，脚本会根据 `arg1` 计算并写入 `acw_sc__v2` Cookie。
/// 这里用等价的置换 + 异或实现，避免在客户端引入 JS 引擎。
class WafSolver {
  const WafSolver._();

  static final RegExp _argReg = RegExp(r"var\s+arg1\s*=\s*'([0-9a-fA-F]{40})'");

  static const String _key = '3000176000856006061501533003690027800375';

  /// 位置置换：输入第 p 位参与输出第 perm[p] 位。
  static const List<int> _perm = [
    6, 28, 34, 31, 33, 18, 30, 23, 9, 8,
    19, 38, 17, 24, 0, 5, 32, 21, 10, 22,
    25, 14, 15, 3, 16, 27, 13, 35, 2, 29,
    11, 26, 4, 36, 1, 39, 37, 7, 20, 12,
  ];

  static bool isChallenge(String body) =>
      body.length < 20000 &&
      (body.contains('var arg1=') || body.contains('acw_sc__v2')) &&
      body.contains('arg1');

  /// 返回应写入的 `acw_sc__v2` 值；解析失败返回 null。
  static String? solveFromHtml(String body) {
    final match = _argReg.firstMatch(body);
    if (match == null) return null;
    final arg1 = match.group(1)!.toLowerCase();
    final out = List<String>.filled(arg1.length, '0');
    for (var p = 0; p < arg1.length; p++) {
      final q = _perm[p];
      final input = int.parse(arg1[p], radix: 16);
      final key = int.parse(_key[q], radix: 16);
      out[q] = (input ^ key).toRadixString(16);
    }
    return out.join();
  }

  /// 从一段 `document.cookie = "..."` 脚本中提取 Cookie 名值（备用方案）。
  static String? solveFromScript(String body) {
    final cookie = RegExp(r'''document\.cookie\s*=\s*['"]([^'"]+)['"]''').firstMatch(body)?.group(1);
    if (cookie == null) return null;
    final pair = cookie.split(';').first.trim();
    return pair.startsWith('acw_sc__v2=') ? pair.substring('acw_sc__v2='.length) : null;
  }

  /// 解析 WAF 挑战页里的 JS（可能被 gzip 压缩，由 HttpSession 负责解压）。
  static String? solve(String body) {
    final direct = solveFromHtml(body);
    if (direct != null) return direct;
    return solveFromScript(body);
  }

  static String decodeUtf8(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);
}
