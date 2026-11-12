import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/forum_link.dart';

/// 站内链接路由的回归测试。
///
/// 起因：楼层链接 `forum.php?mod=redirect&goto=findpost&pid=12088322`
/// 只带 pid，旧路由只认 `thread-x-1-1.html`，点开就掉进内置浏览器，
/// 看起来像没做原生跳转。这里把 Discuz 的几种地址写法一次钉住。
void main() {
  group('主题链接', () {
    test('伪静态', () {
      final link = ForumLink.parse('https://bbs.binmt.cc/thread-12345-1-1.html');
      expect(link, isA<ThreadLink>());
      expect((link as ThreadLink).tid, 12345);
      expect(link.pid, 0);
    });

    test('mod=viewthread 带 tid', () {
      final link = ForumLink.parse('https://bbs.binmt.cc/forum.php?mod=viewthread&tid=888');
      expect(link, isA<ThreadLink>());
      expect((link as ThreadLink).tid, 888);
      expect(link.needsLookup, isFalse);
    });

    test('mod=viewthread 带 pid 时也算楼层', () {
      final link = ForumLink.parse(
        'https://bbs.binmt.cc/forum.php?mod=viewthread&tid=888&pid=77777',
      );
      final thread = link as ThreadLink;
      expect(thread.tid, 888);
      expect(thread.pid, 77777);
    });

    test('findpost 同时带 ptid 与 pid', () {
      final link = ForumLink.parse(
        'https://bbs.binmt.cc/forum.php?mod=redirect&goto=findpost&ptid=8888&pid=77777',
      );
      final thread = link as ThreadLink;
      expect(thread.tid, 8888);
      expect(thread.pid, 77777);
      expect(thread.needsLookup, isFalse);
    });

    test('findpost 只有 pid 时要回头问服务端', () {
      final link = ForumLink.parse(
        'https://bbs.binmt.cc/forum.php?mod=redirect&goto=findpost&pid=12088322',
      );
      final thread = link as ThreadLink;
      expect(thread.tid, 0);
      expect(thread.pid, 12088322);
      expect(thread.needsLookup, isTrue);
    });

    test('HTML 实体与相对路径都能认', () {
      final entity = ForumLink.parse(
        'forum.php?mod=redirect&amp;goto=findpost&amp;ptid=12&amp;pid=34',
      );
      expect((entity as ThreadLink).tid, 12);
      expect(entity.pid, 34);

      final relative = ForumLink.parse('thread-9-1-1.html');
      expect((relative as ThreadLink).tid, 9);
    });
  });

  group('其它站内页面', () {
    test('版块', () {
      expect((ForumLink.parse('https://bbs.binmt.cc/forum-45-1.html') as BoardLink).fid, 45);
      expect(
        (ForumLink.parse('https://bbs.binmt.cc/forum.php?mod=forumdisplay&fid=46') as BoardLink).fid,
        46,
      );
    });

    test('用户空间', () {
      expect((ForumLink.parse('https://bbs.binmt.cc/space-uid-7.html') as UserLink).uid, 7);
      expect(
        (ForumLink.parse('https://bbs.binmt.cc/home.php?mod=space&uid=8') as UserLink).uid,
        8,
      );
    });
  });

  group('不该拦的链接', () {
    test('站外地址原样交给浏览器', () {
      expect(ForumLink.parse('https://example.com/thread-1-1-1.html'), isNull);
      expect(ForumLink.parse('https://bbs.binmt.cc.evil.com/thread-1-1-1.html'), isNull);
    });

    test('插件页、下载页走内置浏览器', () {
      expect(ForumLink.parse('https://bbs.binmt.cc/plugin.php?id=comiis_app'), isNull);
      // 回复页要靠 onReply 回调，不在解析器里处理。
      expect(
        ForumLink.parse('https://bbs.binmt.cc/forum.php?mod=post&action=reply&tid=1'),
        isNull,
      );
    });

    test('空串不炸', () {
      expect(ForumLink.parse(''), isNull);
      expect(ForumLink.parse('   '), isNull);
    });
  });
}
