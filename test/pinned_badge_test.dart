import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';
import 'package:mt_forum/data/models.dart';

/// 网页端用「置顶 来自2#」标注置顶回复：既有标记，也保留它原来的楼层。
/// App 之前两样都读不到，于是置顶回复看起来和普通沙发一模一样；
/// 操作成功的回执又被当成整段 JS 弹了出来。
void main() {
  group('楼层头部的置顶标记', () {
    test('读到「置顶 来自2#」', () {
      final meta = ForumRepository.parseFloorMeta(
        'Aiopr·皇者 Lv.6 硕士生 楼主 置顶 来自2# 6分钟前 天津',
      );

      expect(meta.pinned, isTrue);
      expect(meta.floor, 2);
    });

    test('普通楼层没有置顶标记', () {
      final meta = ForumRepository.parseFloorMeta('Aiopr·皇者 Lv.6 硕士生 6分钟前 天津');

      expect(meta.pinned, isFalse);
      expect(meta.floor, isNull);
    });

    test('只有「置顶」二字不算置顶回复（那是主题被版内置顶）', () {
      final meta = ForumRepository.parseFloorMeta('置顶 3 分钟前');

      expect(meta.pinned, isFalse);
      expect(meta.floor, isNull);
    });

    test('站点给了原楼号时不被 pid 重排覆盖', () {
      ForumPost post(int pid, {int floor = 0, bool pinned = false, bool hasSiteFloor = false}) =>
          ForumPost(
            pid: pid,
            author: 'u$pid',
            avatar: '',
            time: '',
            html: '',
            floor: floor,
            isPinned: pinned,
            hasSiteFloor: hasSiteFloor,
          );

      final posts = <ForumPost>[
        post(100),
        post(200, floor: 2, pinned: true, hasSiteFloor: true), // 置顶的沙发
        post(101),
      ];

      ForumRepository.fixFloorsForPinnedReplies(posts);

      expect(posts[1].floor, 2);
      expect(posts[1].isPinned, isTrue);
      expect(posts[2].floor, 3);
    });
  });

  group('inajax 回执', () {
    test('从脚本参数里取中文提示，而不是把整段 JS 当消息', () {
      const body = '''<?xml version="1.0" encoding="utf-8"?>
<root><![CDATA[<script type="text/javascript" reload="1">if(typeof succeedhandle_mods=='function') {succeedhandle_mods('forum.php?mod=viewthread&tid=175569&page=&mobile=2','管理操作成功','');} setTimeout(function() {window.location.href = 'forum.php?mod=viewthread&tid=175569&page=&mobile=2';}, '3000');</script>]]></root>''';

      final message = ForumRepository.inajaxMessage(body);

      expect(message, '管理操作成功');
      expect(message.contains('succeedhandle'), isFalse);
      expect(message.contains('window.location'), isFalse);
    });

    test('普通 CDATA 文案照原样返回', () {
      const body = '<root><![CDATA[抱歉，您没有权限进行此操作]]></root>';

      expect(ForumRepository.inajaxMessage(body), '抱歉，您没有权限进行此操作');
    });
  });
}
