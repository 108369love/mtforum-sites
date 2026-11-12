import '../data/models.dart';

/// 置顶回复与分页的去重。
///
/// Discuz 只在第 1 页额外插入一份置顶回复（`forum_viewthread.php` 里
/// `$_G['page'] === 1` 才查 `forum_poststick`），它原本所在的那一页
/// 仍会照常返回同一条楼层。所以「14 楼被置顶」时，第 1 页顶部会有一条
/// 带「置顶」标记的 14 楼，翻到第 2 页又会出现一条 14 楼。
///
/// 网页端第 1 页把置顶插进 `$postarr` 后靠 `$postlist[$post['pid']]` 去重，
/// 同一页里不会重复；跨页那份得由客户端自己收尾——把已经置顶展示过的
/// 楼层跳掉，其余楼层保持原有顺序和楼号，不做重编号。
class ThreadPaging {
  const ThreadPaging._();

  /// 一页结果里被站点标记为置顶的楼层 pid。
  static Set<int> pinnedPidsOf(Iterable<ForumPost> posts) =>
      posts.where((post) => post.isPinned).map((post) => post.pid).toSet();

  /// 去掉已经在前面展示过的置顶楼层，顺序与楼号都不动。
  ///
  /// 保留 `isPinned` 的那条：第 1 页顶部本来就是它，不能被自己过滤掉。
  static List<ForumPost> withoutPinnedDuplicates(
    Iterable<ForumPost> posts,
    Set<int> pinnedPids,
  ) {
    if (pinnedPids.isEmpty) return posts.toList();
    return posts
        .where((post) => post.isPinned || !pinnedPids.contains(post.pid))
        .toList();
  }

  /// 判断是否还有下一页。
  ///
  /// 三个信号按可信度排序：
  /// 1. 站点渲染的分页链接（最准，`page=2` 这类 href 直接说明有第 2 页）；
  /// 2. 主题的总楼数——**只有第 1 页的这个数才是全帖总数**。第 2 页以后
  ///    的「回复 N」节点给的是本页条数，比如 16 楼的帖子第 2 页会报 5，
  ///    拿它乘页数算，会提前把「下一页」关掉，所以只在第 1 页采信；
  /// 3. 这一页装满 10 条，大概还有。
  ///
  /// 早先把 3 当成无条件的补充条件，满 10 条的帖子（比如 1 楼 + 9 回复
  /// 正好一页）就永远显示「下一页」，点下去取回来的还是同一页——
  /// 页码跳到 2、内容一丝没变，点多少次都到不了底。
  static bool hasNextPage({
    required int page,
    required int postCount,
    required int total,
    required bool totalKnown,
    required bool linksSayMore,
    int perPage = 10,
  }) {
    if (linksSayMore) return true;
    // 第 1 页的总数是全帖总数，能直接算出总页数。
    if (page == 1 && totalKnown) return total > page * perPage;
    return postCount >= perPage;
  }

  /// 取回来的这一页是不是已经展示过的那一页。
  ///
  /// Discuz 的 `page` 超过总页数时不报错，直接把最后一页再发一遍。
  /// 分页链接的解析一旦有偏差（模板改版、置顶块错位），客户端就会拿
  /// 着「还有下一页」一直请求同一页。这里用 pid 认重：本页所有楼都在
  /// 已经显示的集合里，就是同一页又回来了一次，该收尾了。
  static bool isRepeatedPage(Set<int> shownPids, Iterable<ForumPost> pagePosts) {
    if (shownPids.isEmpty) return false;
    var counted = 0;
    for (final post in pagePosts) {
      if (post.pid <= 0) return false; // pid 不可靠时不作判断
      if (!shownPids.contains(post.pid)) return false;
      counted++;
    }
    if (counted == 0) return false;
    // 少了一条就不是「同一页又回来」：删掉一层之后本页会短一截，
    // 内容是真的变了。早先只要「这一页的楼都见过」就判重复，删完楼
    // 刷新时新页被当成旧页丢掉，列表里还留着刚删掉的那条，
    // 上层据此报「删除未生效」——服务端其实早删干净了。
    return counted == shownPids.length;
  }
}
