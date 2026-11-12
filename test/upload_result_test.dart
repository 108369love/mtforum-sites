import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/upload_result.dart';

/// `misc.php?mod=swfupload&operation=upload` 的返回解析。
///
/// 服务端 `forum_upload` 类有两种输出格式，字段位置不同：
///   带 type：DISCUZUPLOAD|1|0|1234|1|202401/01/abc.jpg|photo.jpg|0
///   不带 type：DISCUZUPLOAD|0|1234|1|0
/// 早期只按后一种硬解，第一种就被判成失败。
void main() {
  test('7 段格式：成功', () {
    const body =
        'DISCUZUPLOAD|1|0|1234|1|202401/01/abc.jpg|photo.jpg|0';
    final r = parseUploadResult(body)!;
    expect(r.ok, isTrue);
    expect(r.aid, 1234);
    expect(r.errorCode, 0);
    expect(r.filename, 'photo.jpg');
  });

  test('7 段格式：附件（非图片）也能解', () {
    const body = 'DISCUZUPLOAD|0|0|7788|0|202401/01/abc.zip|包.zip|0';
    final r = parseUploadResult(body)!;
    expect(r.ok, isTrue);
    expect(r.aid, 7788);
  });

  test('5 段格式：成功', () {
    const body = 'DISCUZUPLOAD|0|4321|1|0';
    final r = parseUploadResult(body)!;
    expect(r.ok, isTrue);
    expect(r.aid, 4321);
  });

  test('错误码原样带出来', () {
    const body = 'DISCUZUPLOAD|1|6|0|0|||0';
    final r = parseUploadResult(body)!;
    expect(r.ok, isFalse);
    expect(r.errorCode, 6);
    expect(r.aid, 0);
  });

  test('hash 校验不过时服务端 exit()，空响应要能识别', () {
    expect(parseUploadResult(''), isNull);
    expect(parseUploadResult('   '), isNull);
  });

  test('返回里夹了 HTML 也不影响', () {
    const body =
        '<br />DISCUZUPLOAD|1|0|99|1|2024/x.jpg|a.jpg|0<script>alert(1)</script>';
    final r = parseUploadResult(body)!;
    expect(r.aid, 99);
    expect(r.filename, 'a.jpg');
  });
}
