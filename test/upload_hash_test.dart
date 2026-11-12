import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/upload_hash.dart';

/// 发帖页的上传凭证解析。站点把 hash 写成 8 位短串，早期按 16 位起步匹配，
/// 结果永远取不到，用户只看到「上传凭证已失效」。
void main() {
  test('8 位短 hash 也要认得（uploadformdata 声明）', () {
    const html = '<script>var uploadformdata = {uid:"34273", hash:"8a7b6c5d"};</script>';
    expect(findUploadHash(html), '8a7b6c5d');
  });

  test('32 位 md5 正常解析', () {
    const html = """uploadformdata:{uid:"1",hash:"e10adc3949ba59abbe56e057f20f883e"}""";
    expect(findUploadHash(html), 'e10adc3949ba59abbe56e057f20f883e');
  });

  test('优先取 uploadformdata 里的，不被页面其它 hash 干扰', () {
    const html = '''
      <script>
        var passwordHash = "ffffffffffffffffffffffffffffffff";
        var uploadformdata = {'uid':'1', 'hash':'abc12345'};
      </script>
    ''';
    expect(findUploadHash(html), 'abc12345');
  });

  test('隐藏域与查询串里的 hash 作为兜底', () {
    expect(findUploadHash('<input type="hidden" name="hash" value="deadbeef" />'), 'deadbeef');
    expect(findUploadHash('<a href="misc.php?mod=swfupload&hash=cafe1234">上传</a>'), 'cafe1234');
  });

  test('页面里确实没有凭证时返回空串', () {
    expect(findUploadHash('<div>普通页面</div>'), '');
    expect(findUploadHash(''), '');
  });

  group('真实发帖页片段（保存时脚本被剥掉）', () {
    // 保存网页会把 inline 脚本整段去掉，discuz_uid 和 uploadformdata 都不在了，
    // 只剩链接里的 formhash、uid。
    const html = '''
      <a href="https://bbs.binmt.cc/member.php?mod=logging&amp;action=logout&amp;formhash=35cecc51&amp;mobile=2">退出</a>
      <a href="https://bbs.binmt.cc/home.php?mod=space&amp;uid=34273&amp;do=profile&amp;mycenter=1">我的</a>
    ''';

    test('uid 从个人中心链接兜底出来', () {
      expect(findUploadUid(html), 34273);
    });

    test('formhash 不能被误当成上传凭证', () {
      expect(findUploadHash(html), '');
    });
  });

  group('手机版发帖表单', () {
    // template/default/mobile/forum/post.htm 的真实结构：
    // 表单里直接放 uid / hash 隐藏域和一个 Filedata 文件框，靠整表单提交上传。
    const html = '''
      <form method="post" id="postform" enctype="multipart/form-data"
            action="forum.php?mod=post&action=newthread&fid=41&extra=&topicsubmit=yes&mobile=yes">
        <input type="hidden" name="formhash" id="formhash" value="35cecc51" />
        <input type="hidden" name="uid" value="34273" />
        <input type="hidden" name="type" value="image" />
        <input type="hidden" name="hash" value="9f2c4b7a1d8e0356c1b4a7d2e5f80193">
        <input type="file" name="Filedata">
      </form>
    ''';

    test('uid 从表单隐藏域读出', () {
      expect(findUploadUid(html), 34273);
    });

    test('hash 从表单隐藏域读出', () {
      expect(findUploadHash(html), '9f2c4b7a1d8e0356c1b4a7d2e5f80193');
    });
  });

  group('桌面版发帖页', () {
    // 桌面模板走 swfupload，凭证以 JS 对象字面量形式写在 post_params 里。
    const html = '''
      <script>
        var swfconfig = {
          upload_url: "misc.php?mod=swfupload&action=swfupload&operation=upload&fid=41",
          post_params: {"uid" : "34273", "hash":"c4ca4238a0b923820dcc509a6f75849b", "type":"image"},
        };
      </script>
    ''';

    test('uid 从 post_params 读出', () {
      expect(findUploadUid(html), 34273);
    });

    test('hash 从 post_params 读出', () {
      expect(findUploadHash(html), 'c4ca4238a0b923820dcc509a6f75849b');
    });
  });

  test('formhash 不会被当成 hash 对', () {
    const html = '<script>var x = {formhash:"35cecc51abc", other:1};</script>';
    expect(findUploadHash(html), '');
  });
}
