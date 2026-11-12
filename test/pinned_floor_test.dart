import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';
import 'package:mt_forum/data/models.dart';

/// 置顶回复会被站点提到第 1 页最前面，但它的楼层号仍是原楼号。
/// 早先按 DOM 顺序从 2 编号，置顶的 11 楼就被显示成「沙发」。
void main() {
  ForumPost post(int pid) => ForumPost(
        pid: pid,
        author: 'u$pid',
        avatar: '',
        time: '',
        html: '',
        floor: 0,
      );

  test('置顶回复保留原楼号，后面的回复照常递增', () {
    final posts = <ForumPost>[
      post(100), // 主题正文
      post(200), // 被置顶的第 11 楼
      for (var pid = 101; pid <= 109; pid++) post(pid), // 沙发…下水道
    ];

    ForumRepository.fixFloorsForPinnedReplies(posts);

    expect(posts[1].floor, 11);
    expect(posts[1].isPinned, isTrue);
    expect(posts[2].floor, 2);
    expect(posts[2].isPinned, isFalse);
    expect(posts.last.floor, 10);
    // 显示顺序不变：置顶帖仍在正文之后的第一位。
    expect(posts[1].pid, 200);
    expect(posts[2].pid, 101);
  });

  test('没有置顶时按 pid 顺序编号', () {
    final posts = <ForumPost>[post(100), post(101), post(102), post(103)];

    ForumRepository.fixFloorsForPinnedReplies(posts);

    expect(posts.map((p) => p.floor).toList(), [0, 2, 3, 4]);
    expect(posts.any((p) => p.isPinned), isFalse);
  });

  test('置顶帖原本在本页中间时也只标记它', () {
    // 5 楼被置顶：DOM 里排到正文后面，真实楼号仍是 5。
    final posts = <ForumPost>[
      post(100),
      post(105),
      post(101),
      post(102),
      post(103),
      post(104),
      post(106),
    ];

    ForumRepository.fixFloorsForPinnedReplies(posts);

    expect(posts[1].pid, 105);
    expect(posts[1].floor, 6);
    expect(posts[2].floor, 2);
    expect(posts[6].floor, 7);
    expect(posts.where((p) => p.isPinned).single.pid, 105);
  });
}
