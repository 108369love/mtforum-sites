import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/thread_paging.dart';
import 'package:mt_forum/data/models.dart';

/// 「下一页」到底能不能点。
///
/// 起因：`thread-175778` 是「1 楼 + 9 条回复」正好装进一页，客户端却一直
/// 显示「下一页」。点下去页码跳到 2，内容一条没变；再点还是同一批楼，
/// 永远到不了底。
///
/// 用 App 里的 MCP 接口拿真站数据对比过三个样本：
/// - 175778：10 楼，第一页报 10 条 → 旧逻辑 `posts.length >= 10` 判成还有；
/// - 175776：7 楼 → 判成没有了，是对的；
/// - 175739：16 楼，第 1 页 10 条、第 2 页 6 条；但第 2 页的「回复 N」
///   报的是 **5**（本页条数），不是 15（全帖条数）。
///
/// 所以：只有第 1 页的总数能拿来算总页数；「装满一页就猜还有」只在
/// 第 1 页数不出来时兜底；跨页再用 pid 认一次重，双保险。
void main() {
  ForumPost post(int pid) => ForumPost(
        pid: pid,
        floor: 0,
        author: 'u$pid',
        avatar: '',
        time: '',
        html: '',
      );

  group('还有没有下一页', () {
    test('正好装满一页、总楼数也正好一页：没有下一页', () {
      // 175778 的形状：10 楼，一页装完。
      final hasMore = ThreadPaging.hasNextPage(
        page: 1,
        postCount: 10,
        total: 10,
        totalKnown: true,
        linksSayMore: false,
      );
      expect(hasMore, isFalse);
    });

    test('第一页装满了，但总数说明后面还有：有下一页', () {
      // 175739 的形状：16 楼。
      expect(
        ThreadPaging.hasNextPage(
          page: 1,
          postCount: 10,
          total: 16,
          totalKnown: true,
          linksSayMore: false,
        ),
        isTrue,
      );
    });

    test('一页都没装满：没有下一页', () {
      // 175776 的形状：7 楼。
      expect(
        ThreadPaging.hasNextPage(
          page: 1,
          postCount: 7,
          total: 7,
          totalKnown: true,
          linksSayMore: false,
        ),
        isFalse,
      );
    });

    test('第 2 页只有 6 楼，即便页面把总数说成 6：没有下一页', () {
      // 第 2 页的「回复 N」是本页条数，不能当成全帖总数。
      expect(
        ThreadPaging.hasNextPage(
          page: 2,
          postCount: 6,
          total: 6,
          totalKnown: true,
          linksSayMore: false,
        ),
        isFalse,
      );
    });

    test('第 2 页装满 10 楼：先当还有，后面交给 pid 认重兜底', () {
      expect(
        ThreadPaging.hasNextPage(
          page: 2,
          postCount: 10,
          total: 10,
          totalKnown: true,
          linksSayMore: false,
        ),
        isTrue,
      );
    });

    test('站点自己渲染了分页链接：以链接为准', () {
      expect(
        ThreadPaging.hasNextPage(
          page: 1,
          postCount: 10,
          total: 10,
          totalKnown: true,
          linksSayMore: true,
        ),
        isTrue,
      );
    });

    test('第一页数不出总数、但装满了一页：保守地继续', () {
      expect(
        ThreadPaging.hasNextPage(
          page: 1,
          postCount: 10,
          total: 10,
          totalKnown: false,
          linksSayMore: false,
        ),
        isTrue,
      );
    });
  });

  group('这一页是不是又发了一遍', () {
    test('楼全都见过：是同一页', () {
      expect(
        ThreadPaging.isRepeatedPage({1, 2, 3}, [post(1), post(2), post(3)]),
        isTrue,
      );
    });

    test('混进来一条新楼：不是同一页', () {
      expect(
        ThreadPaging.isRepeatedPage({1, 2, 3}, [post(1), post(2), post(9)]),
        isFalse,
      );
    });

    test('还没显示过任何楼：不算重复', () {
      expect(ThreadPaging.isRepeatedPage({}, [post(1)]), isFalse);
    });

    test('空页不算重复，交给上层当空态处理', () {
      expect(ThreadPaging.isRepeatedPage({1, 2}, const []), isFalse);
    });

    test('pid 取不到时不下结论，宁可多翻一次', () {
      expect(ThreadPaging.isRepeatedPage({1, 2}, [post(0)]), isFalse);
    });

    test('删掉一层后本页少一条：不算重复，得让新内容进来', () {
      // 线上现象：服务端已经删成功，App 却提示「删除未生效」。
      // 根因是这一页剩下的楼全在旧集合里，被判成「同一页又回来了」，
      // 新页被丢掉，列表里还留着刚删掉的那条。
      expect(
        ThreadPaging.isRepeatedPage({1, 2, 3}, [post(1), post(2)]),
        isFalse,
      );
    });
  });
}
