/// 解析 Discuz `misc.php?mod=swfupload&operation=upload` 的返回。
///
/// 服务端有两种输出（看 `forum_upload` 类走的哪个分支）：
///
/// ```
/// DISCUZUPLOAD|1|0|1234|1|202401/01/abc.jpg|photo.jpg|0     // 带 type，8 段
/// DISCUZUPLOAD|0|1234|1|0                                    // 不带 type，5 段
/// ```
///
/// 两个格式的字段位置不一样，按段数分开解，不能用一个正则硬套。
/// 另外 hash 校验不过时服务端是 `exit()`，响应体为空——那种情况返回 null，
/// 由调用方给出「凭证被拒绝」这类可读提示。
library;

class UploadResult {
  const UploadResult({
    required this.errorCode,
    required this.aid,
    this.attachment = '',
    this.filename = '',
  });

  /// 0 表示成功，其余是 Discuz 的错误码（1–11，见提示文案表）。
  final int errorCode;
  final int aid;
  final String attachment;
  final String filename;

  bool get ok => errorCode == 0 && aid > 0;

  @override
  String toString() => 'UploadResult(error=$errorCode, aid=$aid, file=$filename)';
}

UploadResult? parseUploadResult(String body) {
  final start = body.indexOf('DISCUZUPLOAD');
  if (start < 0) return null;

  final parts = _clean(body.substring(start)).split('|');
  // parts[0] 是 DISCUZUPLOAD 本身，后面才是字段。
  if (parts.length >= 8) {
    // 带 type：|type|error|aid|isimage|attachment|filename|sizelimit
    return UploadResult(
      errorCode: int.tryParse(parts[2]) ?? -1,
      aid: int.tryParse(parts[3]) ?? 0,
      attachment: parts[5],
      filename: parts[6],
    );
  }
  if (parts.length >= 5) {
    // 不带 type：|error|aid|isimage|sizelimit
    return UploadResult(
      errorCode: int.tryParse(parts[1]) ?? -1,
      aid: int.tryParse(parts[2]) ?? 0,
    );
  }
  return null;
}

/// 截掉尾部可能跟着的 HTML / 脚本，避免最后一段被污染。
String _clean(String raw) {
  final cut = raw.indexOf('<');
  return cut >= 0 ? raw.substring(0, cut) : raw;
}
