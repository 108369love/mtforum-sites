/// Discuz 发帖页里的附件上传凭证（uid + hash）。
///
/// 两套模板给的东西不一样：
///
/// * 桌面版：`post_params: {"uid" : "34273", "hash":"32位md5", "type":"image"}`
/// * 手机版：`<input type="hidden" name="uid" value="34273">`
///   `<input type="hidden" name="hash" value="32位md5">`
///
/// 服务端 `misc_swfupload.php` 的校验是硬性的：
///
/// ```php
/// if($_POST['hash'] != md5(substr(md5($authkey), 8).$_POST['uid'])) exit();
/// ```
///
/// 也就是说 hash 必须恰好等于 `md5(站点私钥片段 + uid)`，uid 错一位、hash 空着，
/// 请求都会被服务端直接 exit() 成空白响应。所以这两个值只能从页面上原样读出来。
library;

/// `<input type="hidden" name="uid" value="34273">`，属性顺序两种都认。
final RegExp _uidInputAfter = RegExp(
  r'''name=["']uid["'][^>]*?value=["'](\d+)["']''',
  caseSensitive: false,
);

final RegExp _uidInputBefore = RegExp(
  r'''value=["'](\d+)["'][^>]*?name=["']uid["']''',
  caseSensitive: false,
);

final RegExp _discuzUid = RegExp(r'''discuz_uid\s*=\s*['"]?(\d+)''');

/// `"uid" : "34273"` / `uid:'34273'`。
/// `\b` 保证不会命中 `discuz_uid`（前面是下划线，不是词边界）。
final RegExp _uidPair = RegExp(
  r'''["']?\buid["']?\s*:\s*["']?(\d+)["']?''',
  caseSensitive: false,
);

/// 保存网页会把 inline 脚本整段剥掉，`discuz_uid` 也随之消失；
/// 这时退而求其次看个人中心链接里的 `uid=`。
final RegExp _linkUid = RegExp(r'''[?&;]uid=(\d+)''');

/// 手机版模板的隐藏域。
final RegExp _hashInputAfter = RegExp(
  r'''name=["']hash["'][^>]*?value=["']([0-9a-zA-Z_-]{6,64})["']''',
  caseSensitive: false,
);

final RegExp _hashInputBefore = RegExp(
  r'''value=["']([0-9a-zA-Z_-]{6,64})["'][^>]*?name=["']hash["']''',
  caseSensitive: false,
);

final RegExp _uploadBlock = RegExp(
  r'uploadformdata\s*[:=]\s*\{.{0,300}?\}',
  caseSensitive: false,
  dotAll: true,
);

/// `"hash":"32位md5"`。key 前面不能紧挨字母数字，否则 `formhash` 会被误抓。
final RegExp _hashPair = RegExp(
  r'''(?<![0-9a-zA-Z_])hash["']?\s*:\s*["']([0-9a-zA-Z_-]{6,64})["']''',
  caseSensitive: false,
);

final RegExp _hashQuery = RegExp(
  r'[?&]hash=([0-9a-zA-Z_-]{6,64})',
  caseSensitive: false,
);

String findUploadHash(String html) {
  if (html.isEmpty) return '';
  // 隐藏域最可信：模板直接吐给发帖表单的就是它。
  for (final pattern in [_hashInputAfter, _hashInputBefore]) {
    final match = pattern.firstMatch(html);
    if (match != null) return match.group(1)!;
  }
  // 其次是 uploadformdata 声明里的那个，避免误抓页面里其它叫 hash 的变量。
  final block = _uploadBlock.firstMatch(html);
  if (block != null) {
    final inside = _hashPair.firstMatch(block.group(0)!);
    if (inside != null) return inside.group(1)!;
  }
  // 桌面版走 swfconfig 那套，写成 JS 对象字面量。
  final direct = _hashPair.firstMatch(html);
  if (direct != null) return direct.group(1)!;
  return _hashQuery.firstMatch(html)?.group(1) ?? '';
}

int findUploadUid(String html) {
  for (final pattern in [
    _uidInputAfter,
    _uidInputBefore,
    _discuzUid,
    _uidPair,
    _linkUid,
  ]) {
    final match = pattern.firstMatch(html);
    final value = int.tryParse(match?.group(1) ?? '') ?? 0;
    if (value > 0) return value;
  }
  return 0;
}
