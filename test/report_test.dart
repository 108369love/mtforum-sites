import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';

/// 举报走的是 Discuz 的 `misc.php?mod=report`：一旦参数名或提交方式跑偏，
/// 服务端只会把空表单再渲染一遍，前端却提示“已提交”，信息到不了管理员。
void main() {
  test('举报请求沿用网页端的 misc.php?mod=report 契约', () {
    final request = ForumRepository.reportRequest(
      fid: 3,
      tid: 100,
      pid: 200,
      formhash: 'abc123',
      reason: '广告垃圾',
    );

    expect(request.query['mod'], 'report');
    expect(request.query['rtype'], 'post');
    expect(request.query['rid'], '200');
    expect(request.query['inajax'], '1');
    // submitcheck() 只认 POST，放 query 上会被判成“没提交”。
    expect(request.query.containsKey('reportsubmit'), isFalse);
    expect(request.form['reportsubmit'], 'true');
    expect(request.form['rtype'], 'post');
    expect(request.form['rid'], '200');
    expect(request.form['tid'], '100');
    expect(request.form['fid'], '3');
    expect(request.form['inajax'], '1');
    expect(request.form['formhash'], 'abc123');
    expect(request.form['message'], '广告垃圾');
    expect(request.form['url'], isNotEmpty);
  });

  test('补充说明跟理由一起提交', () {
    final request = ForumRepository.reportRequest(
      fid: 3,
      tid: 100,
      pid: 200,
      formhash: 'abc123',
      reason: '重复发帖',
      message: '  同一段话刷了五遍  ',
    );
    expect(request.form['message'], '重复发帖｜同一段话刷了五遍');
  });

  test('删帖走编辑页的 delete=1（Discuz 没有 action=postdelete）', () {
    final request = ForumRepository.deleteRequest(
      fid: 3,
      tid: 100,
      pid: 200,
      formhash: 'abc123',
      page: 2,
    );

    expect(request.query['mod'], 'post');
    expect(request.query['action'], 'edit');
    expect(request.query['pid'], '200');
    expect(request.query['page'], '2');
    expect(request.query['delete'], '1');
    expect(request.query['action'], isNot('postdelete'));
    // submitcheck('editsubmit') 要求 POST + formhash + 同域 referer。
    expect(request.form['editsubmit'], 'yes');
    expect(request.form['formhash'], 'abc123');
  });

  test('识别站点返回的受理结果', () {
    expect(ForumRepository.reportReplyText('{"message":"举报成功 "}'), '举报成功');
    expect(ForumRepository.reportReplyText('<root><![CDATA[举报成功 ]]></root>'), '举报成功');
    expect(
      ForumRepository.reportReplyText(
        '<html><body><div id="messagetext"><p>页面参数错误，暂不能举报</p></div></body></html>',
      ),
      contains('页面参数错误'),
    );
    expect(ForumRepository.reportReplyText(''), '');
  });
}
