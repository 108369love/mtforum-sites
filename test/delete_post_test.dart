import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';

/// 删帖结果判定的回归测试。
///
/// 线上现象：楼层其实已经删掉，App 却弹「删除未生效」。旧实现把「刷新一次
/// 后列表里还有没有这一楼」当成结果，刷新一旦失败（或被分页位移顶掉），
/// 就对着已删除的楼层报错。现在改成看服务端的三个硬信号。
void main() {
  group('请求契约', () {
    test('删帖走「编辑页 + delete=1」，不是不存在的 postdelete', () {
      final request = ForumRepository.deleteRequest(
        fid: 7,
        tid: 888,
        pid: 77777,
        formhash: 'abcd1234',
        page: 3,
      );
      expect(request.query['mod'], 'post');
      expect(request.query['action'], 'edit');
      expect(request.query['delete'], '1');
      expect(request.query['pid'], '77777');
      expect(request.query['page'], '3');
      expect(request.form['editsubmit'], 'yes');
      expect(request.form['delete'], '1');
      expect(request.form['formhash'], 'abcd1234');
    });
  });

  group('结果判定', () {
    test('落在帖子页且楼层节点消失 = 删除成功', () {
      final failure = ForumRepository.deleteFailure(
        finalUrl: 'https://bbs.binmt.cc/forum.php?mod=viewthread&tid=888&page=2',
        body: '<div id="post_77776">楼上</div>',
        pid: 77777,
      );
      expect(failure, isNull);
    });

    test('落在帖子页但楼层还在 = 没删掉', () {
      final failure = ForumRepository.deleteFailure(
        finalUrl: 'https://bbs.binmt.cc/forum.php?mod=viewthread&tid=888',
        body: '<div id="post_77777"><div id="postmessage_77777">测试</div></div>',
        pid: 77777,
      );
      expect(failure, isNotNull);
      expect(failure, contains('删除未生效'));
    });

    test('停在编辑页 = 服务端把表单退回来了', () {
      final failure = ForumRepository.deleteFailure(
        finalUrl: 'https://bbs.binmt.cc/forum.php?mod=post&action=edit&pid=77777',
        body: '',
        pid: 77777,
      );
      expect(failure, isNotNull);
    });

    test('明确的拒绝语照原样抛出', () {
      final failure = ForumRepository.deleteFailure(
        finalUrl: 'https://bbs.binmt.cc/forum.php?mod=post&action=edit&pid=77777',
        body: '',
        pid: 77777,
        message: '抱歉，您没有权限删除本帖',
      );
      expect(failure, '抱歉，您没有权限删除本帖');
    });

    test('站点公告不算拒绝：感谢分享 + 楼层已消失', () {
      final failure = ForumRepository.deleteFailure(
        finalUrl: 'https://bbs.binmt.cc/forum.php?mod=viewthread&tid=888',
        body: '<div id="post_1">主题</div>',
        pid: 77777,
        message: '感谢分享，期待更多好帖',
      );
      expect(failure, isNull);
    });

    test('别的楼层引用它时不误判：只认楼层容器 id', () {
      // 引用块里会出现 `pid=77777`，但那不是这一楼还在的证据。
      final failure = ForumRepository.deleteFailure(
        finalUrl: 'https://bbs.binmt.cc/forum.php?mod=viewthread&tid=888',
        body: '<a href="forum.php?mod=redirect&goto=findpost&pid=77777">引用</a>',
        pid: 77777,
      );
      expect(failure, isNull);
    });
  });
}
