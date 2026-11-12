import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/pending_upload.dart';

/// 站点手机模板把附件直接放进发帖表单（`<input type="file" name="Filedata">`），
/// 不走 misc.php 的 swfupload。这里确认提交时字段名和网页端完全一致——
/// 服务端就是按这个名字取 $_FILES 的，改一个字都会被当成没带文件。
void main() {
  test('字段名与网页表单一致', () {
    const file = PendingUpload(filename: 'shot.png', bytes: [1, 2, 3]);
    expect(file.field, 'Filedata');
    expect(file.image, isTrue);
  });

  test('附件（非图片）也走同一个字段', () {
    const file = PendingUpload(filename: 'doc.zip', bytes: [0], image: false);
    expect(file.field, 'Filedata');
    expect(file.image, isFalse);
  });
}
