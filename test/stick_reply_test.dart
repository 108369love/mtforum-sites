import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';

/// Discuz 的「置顶回复」是 topicadmin 的确认框表单：`submitcheck('modsubmit')`
/// 需要 query 里带 modsubmit=yes，body 里是 topiclist[] + stickreply。
/// 早先走的版主面板字段（moderate[]）根本不会被执行。
void main() {
  test('置顶回复提交 topicadmin 表单', () {
    final (query, form) = ForumRepository.stickReplyRequest(
      fid: 3,
      tid: 100,
      pid: 200,
      formhash: 'abc123',
      stick: true,
    );

    expect(query['mod'], 'topicadmin');
    expect(query['action'], 'stickreply');
    expect(query['modsubmit'], 'yes');
    expect(query['fid'], '3');
    expect(query['tid'], '100');

    expect(form['topiclist[]'], '200');
    expect(form['stickreply'], '1');
    expect(form['formhash'], 'abc123');
    // 版主面板那一套不该出现在这里。
    expect(form.containsKey('moderate[]'), isFalse);
  });

  test('取消置顶传 stickreply=0', () {
    final (_, form) = ForumRepository.stickReplyRequest(
      fid: 3,
      tid: 100,
      pid: 200,
      formhash: 'abc123',
      stick: false,
    );

    expect(form['stickreply'], '0');
    expect(form['topiclist[]'], '200');
  });
}
