import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/thread_paging.dart';
import 'package:mt_forum/data/models.dart';

/// 置顶回复跨页去重。
///
/// Discuz 只在第 1 页额外插入一份置顶回复，它原本所在的那一页照常返回
/// 同一条。所以 14 楼被置顶时，第 1 页顶部有一条「置顶 14楼」，翻到
/// 第 2 页又会出现一条 14 楼——同一楼显示两次。
///
/// 网页端第 1 页靠 `$postlist[$post['pid']]` 去重，跨页这份要客户端自己收尾：
/// 跳掉已经置顶展示过的楼层，其余楼层顺序和楼号都不动。
void main() {
  ForumPost post(int pid, {int floor = 0, bool pinned = false}) => ForumPost(
        pid: pid,
        author: 'u$pid',
        avatar: '',
        time: '',
        html: '',
        floor: floor,
        isPinned: pinned,
      );

  group('收集置顶楼层', () {
    test('第 1 页顶部那条置顶回复被记下来', () {
      final page1 = <ForumPost>[
        post(100, floor: 1),
        post(214, floor: 14, pinned: true),
        post(101, floor: 2),
      ];
      expect(ThreadPaging.pinnedPidsOf(page1), {214});
    });

    test('没有置顶时是空集合', () {
      final page1 = <ForumPost>[post(100, floor: 1), post(101, floor: 2)];
      expect(ThreadPaging.pinnedPidsOf(page1), isEmpty);
    });
  });

  group('翻页时跳过重复的置顶楼层', () {
    test('第 2 页不再出现已经置顶过的 14 楼', () {
      final page2 = <ForumPost>[
        post(211, floor: 11),
        post(212, floor: 12),
        post(213, floor: 13),
        post(214, floor: 14),
      ];

      final visible = ThreadPaging.withoutPinnedDuplicates(page2, {214});

      expect(visible.map((p) => p.pid), [211, 212, 213]);
    });

    test('跳掉一条之后，其余楼层的楼号照旧，不往前顶', () {
      final page2 = <ForumPost>[
        post(211, floor: 11),
        post(212, floor: 12),
        post(213, floor: 13),
        post(214, floor: 14),
      ];

      final visible = ThreadPaging.withoutPinnedDuplicates(page2, {214});

      expect(visible.map((p) => p.floor), [11, 12, 13]);
    });

    test('第 1 页顶部那条置顶自己不会被过滤掉', () {
      final page1 = <ForumPost>[
        post(100, floor: 1),
        post(214, floor: 14, pinned: true),
        post(101, floor: 2),
      ];

      final visible = ThreadPaging.withoutPinnedDuplicates(page1, {214});

      expect(visible.map((p) => p.pid), [100, 214, 101]);
    });

    test('没有置顶记录时原样返回', () {
      final page2 = <ForumPost>[post(211, floor: 11), post(212, floor: 12)];
      final visible = ThreadPaging.withoutPinnedDuplicates(page2, const {});
      expect(visible.map((p) => p.pid), [211, 212]);
    });
  });
}
