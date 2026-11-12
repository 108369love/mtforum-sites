import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import '../core/app_config.dart';
import '../core/http_session.dart';
import '../core/page_message.dart';
import '../core/pending_upload.dart';
import '../core/recycle_bin.dart';
import '../core/reply_context.dart';
import '../core/thread_paging.dart';
import '../core/upload_hash.dart';
import '../core/upload_result.dart';
import '../core/waf_solver.dart';
import 'models.dart';

/// 论坛数据仓库：负责请求、解析与表单提交。
class ForumRepository {
  ForumRepository._();

  static final ForumRepository instance = ForumRepository._();

  final HttpSession _http = HttpSession.instance;
  String _followingFormhash = '';

  /// 个人列表的分页游标，见 [fetchPersonalList]。
  final Map<String, int> _listCursor = {};

  static const String _loginPath = 'member.php?mod=logging&action=login&mobile=2';

  /// 少数页面（如小黑屋）没有移动模板，需要桌面 UA。
  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  Future<void> init() => _http.init();

  // ---------------------------------------------------------------- 列表

  Future<List<ThreadSummary>> fetchGuide(String view, {int page = 1}) async {
    final result = await _http.get(
      'forum.php',
      query: {'mod': 'guide', 'view': view, 'mobile': '2', 'page': '$page'},
    );
    _ensureOk(result);
    return _parseThreadList(result.body);
  }

  Future<List<ThreadSummary>> fetchBoardThreads(int fid, {int page = 1}) async {
    final result = await _http.get(
      'forum.php',
      query: {'mod': 'forumdisplay', 'fid': '$fid', 'mobile': '2', 'page': '$page'},
    );
    _ensureOk(result);
    return _parseThreadList(result.body);
  }

  Future<List<ThreadSummary>> fetchAnnouncements() async {
    final all = await fetchBoardThreads(AppConfig.announcementFid);
    return all.take(4).toList();
  }

  /// 我的主题 / 我的回复 / 我的收藏等页面。
  ///
  /// 回收站主题（用户自己删掉的帖子）会被解析层直接跳过，但它们在页面上
  /// 仍然占着条数：删得多的时候一页可能只剩两三条。上层 ThreadFeed 是按
  /// 「这一批满不满 10 条」判断还有没有下一页的，不补就会以为到底了，
  /// 后面的正常帖子再也翻不出来。所以这里发现本页有被筛掉的条目时，
  /// 继续往下拉几页凑够一页。
  ///
  /// 补页会让游标跑到上层以为的页码前面（上层按自己的请求次数计数），
  /// 所以每份列表记一个 [_listCursor]，下一次从后面接着拉，避免重复。
  Future<List<ThreadSummary>> fetchPersonalList(String path, {Map<String, String>? query}) async {
    final key = _cursorKey(path, query);
    final requested = int.tryParse(query?['page'] ?? '') ?? 0;
    // 第一页意味着重新加载（进页面 / 下拉刷新），游标从头开始。
    if (requested <= 1) _listCursor.remove(key);

    var start = requested;
    if (requested > 1) {
      final cursor = _listCursor[key] ?? 0;
      if (cursor >= requested) start = cursor + 1;
    }

    var raw = 0;
    void count(int value) => raw = value;

    final result = await _http.get(
      path,
      query: {...?query, if (requested > 0) 'page': '$start'},
    );
    _ensureOk(result);
    var list = _parseThreadList(result.body, onRaw: count);
    if (list.isEmpty) list = _parseLooseThreads(result.body, onRaw: count);
    if (requested > 0) _listCursor[key] = start;

    // 没有页码的入口、空页，或本页一条没被筛掉，都不需要补。
    if (requested <= 0 || raw == 0 || list.length >= raw) return list;

    final collected = <ThreadSummary>[...list];
    while (collected.length < AppConfig.pageSize && start < requested + 5) {
      start++;
      final more = await _http.get(path, query: {...?query, 'page': '$start'});
      if (!more.ok) break;
      var rawMore = 0;
      var batch = _parseThreadList(more.body, onRaw: (value) => rawMore = value);
      if (batch.isEmpty) batch = _parseLooseThreads(more.body, onRaw: (value) => rawMore = value);
      // 这一页本来就没内容，说明翻到底了。
      if (rawMore == 0) break;
      collected.addAll(batch);
      _listCursor[key] = start;
      if (batch.length == rawMore) break;
    }
    return collected;
  }

  /// 分页游标。列表按「路径 + 除 page 外的全部参数」区分，
  /// 我的主题 / 我的回复 / TA的主题各存各的。
  String _cursorKey(String path, Map<String, String>? query) {
    final rest = <String, String>{...?query}..remove('page');
    final keys = rest.keys.toList()..sort();
    return '$path?${keys.map((k) => '$k=${rest[k]}').join('&')}';
  }

  Future<List<ForumCategory>> fetchBoards() async {
    final result = await _http.get('forum.php', query: {'forumlist': '1', 'mobile': '2'});
    _ensureOk(result);
    final doc = parser.parse(result.body);
    final categories = <ForumCategory>[];
    for (final group in doc.querySelectorAll('.comiis_forumlist')) {
      final title = _clean(group.querySelector('h2 a')?.text ?? group.querySelector('h2')?.text ?? '');
      final boards = <ForumBoard>[];
      for (final a in group.querySelectorAll('.comiis_forum_nbox li a')) {
        final href = a.attributes['href'] ?? '';
        final fid = _firstInt(RegExp(r'forum-(\d+)-1\.html').firstMatch(href)?.group(1));
        if (fid == null) continue;
        final img = a.querySelector('img');
        final badge = _clean(a.querySelector('em span')?.text ?? '');
        final name = _clean(a.querySelector('p')?.text ?? img?.attributes['alt'] ?? '');
        if (name.isEmpty) continue;
        boards.add(ForumBoard(
          fid: fid,
          name: name,
          icon: _absolute(img?.attributes['src']),
          todayPosts: int.tryParse(badge) ?? 0,
        ));
      }
      if (boards.isNotEmpty) {
        categories.add(ForumCategory(
          name: title.isEmpty ? '版块' : title,
          boards: boards,
        ));
      }
    }
    return categories;
  }

  // ---------------------------------------------------------------- 详情

  /// 楼层链接（`mod=redirect&goto=findpost&pid=x`）→ 主题编号。
  ///
  /// 这类链接只带楼号，Discuz 收到后会 302 到 `mod=viewthread&tid=x&page=n`，
  /// 跟随后从最终地址里取 tid；站点若直接渲染、地址还停在 redirect 上，
  /// 就退回页面里的 canonical / 楼层链接再认一次。
  Future<int> resolveThreadIdByPid(int pid) async {
    if (pid <= 0) return 0;
    final result = await _http.get('forum.php', query: {
      'mod': 'redirect',
      'goto': 'findpost',
      'pid': '$pid',
      'mobile': '2',
    });
    final fromUri = _threadIdOf(result.uri.toString());
    if (fromUri > 0) return fromUri;
    final doc = parser.parse(result.body);
    final canonical = doc.querySelector('link[rel="canonical"]')?.attributes['href'] ?? '';
    final fromCanonical = _threadIdOf(canonical);
    if (fromCanonical > 0) return fromCanonical;
    return 0;
  }

  int _threadIdOf(String href) {
    final match = RegExp(r'[?&](?:amp;)?(?:ptid|tid)=(\d+)').firstMatch(href) ??
        RegExp(r'thread-(\d+)-').firstMatch(href);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  Future<ThreadDetail> fetchThread(
    int tid, {
    int page = 1,
    int? authorId,
    bool orderDesc = false,
    int? pid,
  }) async {
    final query = <String, String>{
      'mod': 'viewthread',
      'tid': '$tid',
      'mobile': '2',
      // 带 pid 时服务端会 302 到该楼所在的页，page 传了反而可能把它顶掉，
      // 所以两者只留一个：定位单楼优先级高于翻页。
      if (pid != null && pid > 0) 'pid': '$pid' else 'page': '$page',
    };
    if (authorId != null && authorId > 0) query['authorid'] = '$authorId';
    if (orderDesc) query['ordertype'] = '1';
    final result = await _http.get('forum.php', query: query);
    _ensureOk(result);
    final html = result.body;
    final doc = parser.parse(html);

    // 带 pid 时服务端会 302 到该楼所在的那一页，返回的已经是第 N 页。
    // 页码不纠正的话，「上一页 / 下一页」还按 1 算，翻一页就跳错；
    // 首条回复也会被当成主题正文排版。
    var currentPage = page;
    if (pid != null && pid > 0) {
      final fromUri = int.tryParse(result.uri.queryParameters['page'] ?? '') ?? 0;
      final fromDoc = _currentPageOf(doc);
      if (fromUri > 0) {
        currentPage = fromUri;
      } else if (fromDoc > 0) {
        currentPage = fromDoc;
      }
    }

    final title = _clean(
      (doc.querySelector('title')?.text ?? '').replaceAll(RegExp(r'\s*-\s*MT论坛\s*$'), ''),
    );

    var boardName = '';
    final keywords = doc.querySelector('meta[name=keywords]')?.attributes['content'] ?? '';
    final parts = keywords.split(',').map(_clean).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2 && parts[1] != AppConfig.siteName && !parts[1].startsWith('MT')) {
      boardName = parts[1];
    }

    var fid = 0;
    for (final form in doc.querySelectorAll('form')) {
      final action = form.attributes['action'] ?? '';
      final match = RegExp(r'[?&]fid=(\d+)').firstMatch(action);
      if (match != null) {
        fid = int.tryParse(match.group(1)!) ?? 0;
        break;
      }
    }
    if (fid == 0) {
      final link = doc.querySelector(r'a[href*="forum-"][href$="-1.html"]');
      final match = RegExp(r'forum-(\d+)-1\.html').firstMatch(link?.attributes['href'] ?? '');
      fid = int.tryParse(match?.group(1) ?? '') ?? 0;
      if (boardName.isEmpty) boardName = _clean(link?.text ?? '');
    }

    final posts = <ForumPost>[];
    for (final el in doc.querySelectorAll('.comiis_postli')) {
      final post = _parsePost(el, posts.length + 1);
      if (post != null) posts.add(post);
    }
    // 只有主题第一页、正常正序且未筛选作者时，首条才是主题正文。
    // 每页解析时 floor 都从 1 重新计数，不能据此把后续页面第一条回复误标为正文。
    final hasThreadOpener = currentPage == 1 && !orderDesc && authorId == null;
    for (var i = 0; i < posts.length; i++) {
      final isOpener = hasThreadOpener && i == 0;
      // 主题正文不参与置顶：主题被版内置顶时首楼也会带「置顶」字样，
      // 那是主题的置顶，不是「置顶回复」。
      posts[i] = posts[i].copyWith(
        isOp: isOpener,
        isPinned: isOpener ? false : null,
        hasSiteFloor: isOpener ? false : null,
        floor: isOpener ? 1 : null,
      );
    }
    // 置顶回复会被提到主题正文后面，但站点给它的楼层号仍是原楼号
    // （forum_viewthread 里 `$post['position'] = $poststick[...]['position']`）。
    // 同一主题内 pid 按发帖顺序递增，所以按 pid 排序就能还原真实楼层，
    // 也能认出「排在前面的那条其实是个高楼层」——那正是被置顶的回复。
    // 早先按 DOM 顺序从 2 编号，置顶帖就被叫成「沙发」，后面全部错位。
    if (hasThreadOpener && posts.length > 1) {
      fixFloorsForPinnedReplies(posts);
    }
    // 站点没给出楼号时，按显示顺序补一个，跳过置顶占用的楼号。
    if (hasThreadOpener) {
      final usedFloors = posts.where((p) => p.hasSiteFloor || p.isPinned).map((p) => p.floor).toSet();
      var nextFloor = 2;
      for (var i = 0; i < posts.length; i++) {
        final post = posts[i];
        if (post.isOp || post.isPinned) continue;
        while (usedFloors.contains(nextFloor)) {
          nextFloor++;
        }
        posts[i] = post.copyWith(floor: nextFloor);
        nextFloor++;
      }
    }
    // 楼主楼层偶发取不到 uid，退回用楼顶作者区再补一次。
    if (posts.isNotEmpty && posts.first.uid == 0) {
      final href = doc.querySelector('.comiis_postli_top a[href*="uid="]')?.attributes['href'] ?? '';
      final uid = int.tryParse(RegExp(r'[?&]uid=(\d+)').firstMatch(href)?.group(1) ?? '') ?? 0;
      if (uid > 0) {
        final first = posts.first;
        posts[0] = first.copyWith(
          uid: uid,
          avatar: first.avatar.isEmpty ? _avatarForUid(uid) : null,
        );
      }
    }

    // `total` 是「这帖一共多少楼」。第 1 页的「回复 N」节点给的是全帖数，
    // 第 2 页以后给的是本页条数，所以只有第 1 页这个数能拿去算总页数；
    // `totalKnown` 就是标记它到底是从页面读到的、还是退回的 posts.length。
    var total = posts.length;
    var totalKnown = false;
    final commentNode = doc.querySelector('.comiis_pltit h2');
    if (commentNode != null) {
      final match = RegExp(r'(\d+)').firstMatch(commentNode.text.replaceAll(',', ''));
      if (match != null) {
        total = (int.tryParse(match.group(1)!) ?? 0) + 1;
        totalKnown = true;
      }
    }
    if (posts.length <= 1 && total <= 1) total = posts.length;

    final formhash = _findFormhash(html);
    final loggedIn = _http.hasLoginCookie || _isLoggedInHtml(html);
    final notice = posts.isEmpty ? _pageMessage(doc) ?? '' : '';

    // 站点插件 bin_post_report 会在页面尾部注入「踢帖(n/5)」入口。
    final kickUrl = RegExp(
      r'plugin\.php\?id=bin_post_report&(?:amp;)?tid=(\d+)&(?:amp;)?m=([0-9A-Za-z]+)',
    ).firstMatch(html);
    final kickLabel = RegExp(r'踢帖\s*\(\s*(\d+)\s*/\s*(\d+)\s*\)').firstMatch(html);

    return ThreadDetail(
      tid: tid,
      title: title,
      fid: fid,
      boardName: boardName,
      author: posts.isNotEmpty ? posts.first.author : '',
      time: posts.isNotEmpty ? posts.first.time : '',
      views: 0,
      replies: math.max(0, total - 1),
      posts: posts,
      formhash: formhash,
      hasMore: ThreadPaging.hasNextPage(
        page: currentPage,
        postCount: posts.length,
        total: total,
        totalKnown: totalKnown,
        linksSayMore: _hasNextThreadPage(doc, currentPage, tid),
        perPage: AppConfig.postsPerPage,
      ),
      page: currentPage,
      isLoggedIn: loggedIn,
      likes: _intOf(doc.querySelector('.comiis_recommend_num')?.text ?? doc.querySelector('#recommendv_add')?.text),
      dislikes: _intOf(doc.querySelector('#recommendv_subtract')?.text),
      liked: threadLiked(doc),
      likeHref: _absolute(recommendHref(doc)),
      uploadHash: findUploadHash(html),
      uid: findUploadUid(html),
      poll: _parsePoll(doc),
      notice: notice,
      favorited: _isThreadFavorited(html),
      favoriteHref: _favoriteHref(html),
      kickToken: kickUrl?.group(2) ?? '',
      kickVotes: int.tryParse(kickLabel?.group(1) ?? '') ?? 0,
      kickLimit: int.tryParse(kickLabel?.group(2) ?? '') ?? 5,
    );
  }

  /// 页面上标着「当前是第几页」的节点。
  ///
  /// 只在带 pid 请求时用来兜底：站点通常 302 到 `...&page=N`，地址里就有；
  /// 少数模板直接渲染、地址仍只带 pid，这时只能读分页控件。
  int _currentPageOf(Document doc) {
    const selectors = <String>[
      '.pg strong',
      '.pg b',
      '.pg .cur',
      '.comiis_page strong',
      '.comiis_page .cur',
      '.pgb strong',
    ];
    for (final selector in selectors) {
      final value = int.tryParse(_clean(doc.querySelector(selector)?.text ?? ''));
      if (value != null && value > 0) return value;
    }
    return 0;
  }

  /// 优先读取 Discuz 页面实际分页链接；部分主题页的回复总数节点并不可靠，
  /// 只按 total 推算会把“下一页”错误地隐藏。
  bool _hasNextThreadPage(Document doc, int currentPage, int tid) {
    for (final link in doc.querySelectorAll(
      '.pg a[href], .comiis_page a[href], a[href*="mod=viewthread"][href*="page="], a[href*="viewthread-"]',
    )) {
      final href = (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
      // 相关主题、本版推荐这些区块里也全是帖子链接，其中指向别的主题
      // 第 2 页的，会被当成「本帖还有下一页」，得先认一下 tid。
      if (!_isSameThread(href, tid)) continue;
      final queryPage = RegExp(r'(?:[?&])page=(\d+)').firstMatch(href)?.group(1);
      final prettyPage = RegExp(r'viewthread-\d+-(\d+)-\d+\.html').firstMatch(href)?.group(1);
      final targetPage = int.tryParse(queryPage ?? prettyPage ?? '');
      if (targetPage != null && targetPage > currentPage) return true;
      final label = _clean(link.text);
      if (targetPage == null &&
          (label == '下一页' || label == '下页' || label == '»' || label == '›') &&
          !link.classes.contains('nxt_disabled') &&
          !link.classes.contains('disabled')) {
        return true;
      }
    }
    return false;
  }

  /// 链接是否指向本帖。认不出 tid 时放行，宁可多翻一页也别漏页。
  bool _isSameThread(String href, int tid) {
    if (tid <= 0) return true;
    final match = RegExp(r'thread-(\d+)-').firstMatch(href) ??
        RegExp(r'[?&](?:amp;)?tid=(\d+)').firstMatch(href);
    final linkTid = match?.group(1);
    if (linkTid == null) return true;
    return linkTid == '$tid';
  }

  /// 解析投票区块：兼容存在可投票表单与仅展示结果两种页面。
  Poll? _parsePoll(Document doc) {
    final container = doc.querySelector(
      '.comiis_poll, #poll, .poll, .comiis_pollbox, .pollpanel, form[action*="votepoll"]',
    );
    if (container == null) return null;

    final options = <PollOption>[];
    var multiple = false;
    for (final input in container.querySelectorAll('input')) {
      final type = (input.attributes['type'] ?? '').toLowerCase();
      if (type != 'radio' && type != 'checkbox') continue;
      final name = input.attributes['name'] ?? '';
      if (!name.contains('pollanswer') && !name.contains('polloption')) continue;
      final id = int.tryParse(input.attributes['value'] ?? '') ?? 0;
      if (id <= 0) continue;
      if (type == 'checkbox') multiple = true;
      final raw = _clean(input.parent?.text ?? '');
      final votes = RegExp(r'(\d+)\s*票').firstMatch(raw)?.group(1);
      final text = raw
          .replaceAll(RegExp(r'[（(]?\s*\d+\s*票[）)]?'), '')
          .replaceAll(RegExp(r'\d+(\.\d+)?%'), '')
          .trim();
      if (text.isEmpty) continue;
      options.add(PollOption(id: id, text: text, votes: int.tryParse(votes ?? '') ?? 0));
    }

    if (options.isEmpty) {
      for (final label in container.querySelectorAll('label, li, .polloption')) {
        final text = _clean(label.text);
        if (text.isEmpty || text.length > 80) continue;
        final votes = RegExp(r'(\d+)\s*票').firstMatch(text);
        options.add(PollOption(
          id: 0,
          text: text.replaceAll(RegExp(r'[（(]?\s*\d+\s*票[）)]?'), '').trim(),
          votes: int.tryParse(votes?.group(1) ?? '') ?? 0,
        ));
      }
    }
    if (options.isEmpty) return null;

    final text = _clean(container.text);
    final total = int.tryParse(RegExp(r'共\s*(\d+)\s*人参与').firstMatch(text)?.group(1) ?? '') ??
        options.fold<int>(0, (sum, option) => sum + option.votes);
    final hasForm = container.querySelector('input[type=radio], input[type=checkbox]') != null;
    return Poll(
      options: options,
      multiple: multiple || text.contains('多选'),
      total: total,
      voted: !hasForm && options.any((option) => option.votes > 0),
      expired: text.contains('投票已结束') || text.contains('已结束'),
    );
  }

  /// 从楼层头部（作者、时间、楼层那些文字）里读出置顶标记与原楼号。
  ///
  /// 网页端把置顶回复标成「置顶 来自2#」：前面是标记，后面是它原来的楼层。
  /// 老版本只认 `来自N#` 且只在少数 class 里找，所以置顶回复在 App 里既没有
  /// 标记也丢了原楼号，看上去和普通沙发一样。
  ///
  /// 只认「来自N#」这一条：主题被版内置顶时首楼也会出现「置顶」二字，只看
  /// 这两个字会把主题正文本身标成置顶回复。没有「来自N#」的置顶回复，仍可
  /// 由 [fixFloorsForPinnedReplies] 按楼号是否被前移认出来。
  @visibleForTesting
  static ({int? floor, bool pinned}) parseFloorMeta(String text) {
    final siteFloor = int.tryParse(
      RegExp(r'来自\s*(\d+)\s*#').firstMatch(text)?.group(1) ?? '',
    );
    return (floor: siteFloor, pinned: siteFloor != null);
  }

  /// 按 pid 还原楼层，并标出被置顶前移的回复。
  ///
  /// `posts[0]` 是主题正文，其余按 pid 升序编号（2、3、4…），再按原来的
  /// 显示顺序写回。谁的排序位置比它在页面里的位置靠后，谁就是被置顶提到
  /// 前面来的那一条。
  ///
  /// 站点已经给出原楼号的（「来自2#」）先占住那个号，其余回复按 pid 顺序
  /// 补空号——否则置顶回复本来就在 2 楼时，pid 最小的是它，会被别人抢走 2。
  @visibleForTesting
  static void fixFloorsForPinnedReplies(List<ForumPost> posts) {
    if (posts.length < 2) return;
    final replies = posts.sublist(1);
    final order = List<int>.generate(replies.length, (i) => i)
      ..sort((a, b) => replies[a].pid.compareTo(replies[b].pid));
    final taken = replies.where((p) => p.hasSiteFloor).map((p) => p.floor).toSet();
    var next = 2;
    for (final domIndex in order) {
      final post = replies[domIndex];
      if (post.hasSiteFloor) continue;
      while (taken.contains(next)) {
        next++;
      }
      posts[domIndex + 1] = post.copyWith(
        floor: next,
        // 楼号比它显示的位置靠后 = 被前面插入的置顶回复挤下去了，不是置顶者；
        // 楼号比显示位置靠前 = 它自己被提到了前面。
        isPinned: post.isPinned || next > domIndex + 2,
      );
      taken.add(next);
      next++;
    }
  }

  ForumPost? _parsePost(Element el, int floor) {
    final pidMatch = RegExp(r'pid(\d+)').firstMatch(el.attributes['id'] ?? '');
    if (pidMatch == null) return null;
    final pid = int.tryParse(pidMatch.group(1)!) ?? 0;

    // 楼层头部（作者、等级、时间、楼层号、置顶标记）单独取一份文本。
    // 先把正文、点评、评分整块摘掉，正文里出现「置顶」二字才不会把普通回复
    // 误判成置顶；手机模板把置顶标记放在作者行右侧，class 各家不同，只能按
    // 「整层减去正文」来读。
    final metaEl = el.clone(true);
    for (final selector in [
      '.comiis_messages',
      '.comiis_message_table',
      '.message',
      '.cm',
      '.comiis_comment',
      '.comment',
      '.comiis_view_lcrate',
      'script',
      'style',
    ]) {
      for (final node in metaEl.querySelectorAll(selector)) {
        node.remove();
      }
    }
    final metaText = _clean(metaEl.text);
    final meta = parseFloorMeta(metaText);
    final isPinned = meta.pinned;
    final originalFloor = meta.floor ?? floor;

    final author = _clean(el.querySelector('.top_user')?.text ?? '');
    final uid = _postUid(el);
    var avatar = _postAvatar(el);
    if (avatar.isEmpty && uid > 0) avatar = _avatarForUid(uid);
    final level = _clean(el.querySelector('.top_lev')?.text ?? '');
    final timeNode = el.querySelector('.comiis_postli_time') ?? el.querySelector('.comiis_postli_times');
    var time = _clean(timeNode?.text ?? '');
    final location = _clean(el.querySelector('.comiis_iplocality')?.text ?? '').replaceAll(RegExp(r'^来自\s*'), '');
    if (location.isNotEmpty) time = time.replaceAll(location, '').trim();
    // 「9 分钟前 来自」这种没有地区名时，尾部会残留一个「来自」，
    // 引用到回复里就会变成「某某 发表于 9 分钟前 来自」。
    time = time.replaceAll(RegExp(r'\s*来自\s*\S*$'), '').trim();

    final contentEl = el.querySelector('.comiis_messages') ??
        el.querySelector('.comiis_message_table') ??
        el.querySelector('.message');
    if (contentEl == null) return null;

    final images = <String>[];
    for (final img in contentEl.querySelectorAll('img')) {
      final src = _pickImage(img);
      if (src.isNotEmpty && !images.contains(src)) images.add(src);
    }

    // 楼层标题（`Re: 主题名`）不是正文，丢掉再渲染。
    final body = contentEl.clone(true);
    removeFloorSubject(body);

    return ForumPost(
      pid: pid,
      author: author,
      avatar: avatar,
      time: time,
      html: _sanitize(body.innerHtml),
      floor: originalFloor,
      isPinned: isPinned,
      hasSiteFloor: meta.floor != null,
      uid: uid,
      level: level,
      location: location,
      isOp: false,
      likes: _intOf(el.querySelector('.comiis_recommend_num')?.text),
      images: images,
      comments: _parseComments(el),
      rates: _parseRates(el, pid),
      rateSummary: _clean(el.querySelector('.comiis_rate a[href*="viewratings"]')?.text ?? ''),
    );
  }

  /// 打赏记录：`#ratelog_<pid>` 内每条 `li#rate_<pid>_<uid>`。
  List<RateRecord> _parseRates(Element el, int pid) {
    final box = el.querySelector('#ratelog_$pid') ?? el.querySelector('.comiis_view_lcrate');
    if (box == null) return const <RateRecord>[];
    final records = <RateRecord>[];
    for (final li in box.querySelectorAll('li')) {
      final score = _clean(li.querySelector('.f_a')?.text ?? '');
      final link = li.querySelector('a.f_c') ?? li.querySelector('a[href*="uid="]');
      final name = _clean(link?.text ?? '');
      final reason = _clean(li.querySelector('p')?.text ?? '');
      if (name.isEmpty && score.isEmpty) continue;
      final uid = _firstInt(
            RegExp(r'[?&]uid=(\d+)').firstMatch(link?.attributes['href'] ?? '')?.group(1),
          ) ??
          0;
      records.add(RateRecord(username: name, uid: uid, score: score, reason: reason));
      if (records.length >= 20) break;
    }
    return records;
  }

  /// 楼中楼点评：兼容 Discuz 手机模板与桌面模板的几种容器。
  List<ForumComment> _parseComments(Element el) {
    final comments = <ForumComment>[];
    for (final container in el.querySelectorAll('.cm, .comiis_comment, .comment')) {
      var items = container.querySelectorAll('.cm_item');
      if (items.isEmpty) {
        items = container.children.where((child) => _clean(child.text).isNotEmpty).toList();
      }
      for (final item in items) {
        final text = _clean(item.querySelector('.cm_text')?.text ?? item.text);
        if (text.isEmpty || text.length > 600) continue;
        final authorLink = item.querySelector('.cm_name, a[href*="uid="]');
        final author = _clean(authorLink?.text ?? '');
        final uid = _firstInt(RegExp(r'[?&]uid=(\d+)').firstMatch(authorLink?.attributes['href'] ?? '')?.group(1)) ?? 0;
        final time = _clean(item.querySelector('.cm_time')?.text ?? '');
        comments.add(ForumComment(author: author, text: text, uid: uid, time: time));
        if (comments.length >= 30) return comments;
      }
    }
    return comments;
  }

  // ---------------------------------------------------------------- 账号

  Future<UserProfile> login(String username, String password, {int questionId = 0, String answer = ''}) async {
    final page = await _http.get(_loginPath);
    _ensureOk(page);
    final formHash = _findFormhash(page.body);
    final action = RegExp(r'<form[^>]+action="([^"]*loginsubmit[^"]*)"', caseSensitive: false)
        .firstMatch(page.body)
        ?.group(1)
        ?.replaceAll('&amp;', '&');
    if (formHash.isEmpty || action == null) {
      throw SiteException(_pageMessage(parser.parse(page.body)) ?? '登录页加载失败，请稍后重试');
    }

    final response = await _http.post(
      action,
      referer: AppConfig.uri(_loginPath).toString(),
      form: {
        'formhash': formHash,
        'referer': AppConfig.base,
        'fastloginfield': 'username',
        'cookietime': '31104000',
        'username': username,
        'password': password,
        'questionid': '$questionId',
        'answer': answer,
      },
    );

    final ok = _http.hasLoginCookie ||
        response.body.contains('欢迎您回来') ||
        response.body.contains('登录成功') ||
        response.body.contains('您已登录');
    if (!ok) {
      final doc = parser.parse(response.body);
      final msg = _pageMessage(doc);
      if (msg != null && msg.isNotEmpty) throw SiteException(msg);
      throw SiteException('登录失败，请检查用户名或密码');
    }
    return fetchMyProfile(fallbackName: username);
  }

  Future<UserProfile> fetchMyProfile({String fallbackName = ''}) async {
    final result = await _http.get(
      'home.php',
      query: {'mod': 'space', 'do': 'profile', 'mobile': '2'},
    );
    _ensureOk(result);
    return _parseSpaceProfile(parser.parse(result.body), result.body, fallbackName: fallbackName);
  }

  Future<void> logout() async {
    _http.clear();
  }

  // ------------------------------------------------------------ 资料设置

  /// 资料设置的三块表单都在 `mod=spacecp&ac=profile` 下，靠 `op` 区分。
  /// 站点把每个字段的可见范围塞进 `privacy[字段]`，居住地则是由省市区街道
  /// 四个隐藏字段拼出的文本，页面上只渲染拼好的那一串。
  static String _profilePath(String op) => 'home.php?mod=spacecp&ac=profile&op=$op&mobile=2';

  Future<ProfileBaseSettings> fetchProfileBase() async {
    final result = await _http.get(
      'home.php',
      query: {'mod': 'spacecp', 'ac': 'profile', 'op': 'base', 'mobile': '2'},
    );
    _ensureOk(result);
    return parseProfileBaseHtml(result.body);
  }

  Future<ProfileContactSettings> fetchProfileContact() async {
    final result = await _http.get(
      'home.php',
      query: {'mod': 'spacecp', 'ac': 'profile', 'op': 'contact', 'mobile': '2'},
    );
    _ensureOk(result);
    return parseProfileContactHtml(result.body);
  }

  Future<ProfileInfoSettings> fetchProfileInfo() async {
    final result = await _http.get(
      'home.php',
      query: {'mod': 'spacecp', 'ac': 'profile', 'op': 'info', 'mobile': '2'},
    );
    _ensureOk(result);
    return parseProfileInfoHtml(result.body);
  }

  Future<PrivacySettings> fetchPrivacySettings() async {
    final result = await _http.get(
      'home.php',
      query: {'mod': 'spacecp', 'ac': 'privacy', 'op': 'base', 'forcemobile': '1'},
    );
    _ensureOk(result);
    return parsePrivacyHtml(result.body);
  }

  @visibleForTesting
  static ProfileBaseSettings parseProfileBaseHtml(String html) {
    final doc = parser.parse(html);
    final fields = _formValues(_profileForm(doc, 'op=base'));
    final box = doc.querySelector('#residedistrictbox');
    // 「天津市 大港区 [修改]」——[修改] 是弹层触发器，不属于地址。
    final reside = (box?.text ?? '')
        .replaceAll('[修改]', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return ProfileBaseSettings(
      formhash: fields['formhash'] ?? _findFormhash(html),
      occupation: fields['occupation'] ?? '',
      realname: fields['realname'] ?? '',
      gender: int.tryParse(fields['gender'] ?? '0') ?? 0,
      birthYear: fields['birthyear'] ?? '',
      birthMonth: fields['birthmonth'] ?? '',
      birthDay: fields['birthday'] ?? '',
      resideText: reside,
      privacy: _privacyOf(fields),
    );
  }

  @visibleForTesting
  static ProfileContactSettings parseProfileContactHtml(String html) {
    final doc = parser.parse(html);
    final fields = _formValues(_profileForm(doc, 'op=contact'));
    final email = doc
            .querySelector('#email, [name="email"]')
            ?.attributes['value']
            ?.trim() ??
        RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+').firstMatch(doc.text ?? '')?.group(0) ??
        '';
    return ProfileContactSettings(
      formhash: fields['formhash'] ?? _findFormhash(html),
      qq: fields['qq'] ?? '',
      mobile: fields['mobile'] ?? '',
      email: email,
      privacy: _privacyOf(fields),
    );
  }

  @visibleForTesting
  static ProfileInfoSettings parseProfileInfoHtml(String html) {
    final doc = parser.parse(html);
    final fields = _formValues(_profileForm(doc, 'op=info'));
    return ProfileInfoSettings(
      formhash: fields['formhash'] ?? _findFormhash(html),
      bio: fields['bio'] ?? '',
      customStatus: fields['customstatus'] ?? '',
      signature: fields['sightml'] ?? '',
      privacy: _privacyOf(fields),
    );
  }

  @visibleForTesting
  static PrivacySettings parsePrivacyHtml(String html) {
    final doc = parser.parse(html);
    final fields = _formValues(_profileForm(doc, 'ac=privacy'));
    return PrivacySettings(
      formhash: fields['formhash'] ?? _findFormhash(html),
      friend: fields['privacy[view][friend]'] ?? '0',
      wall: fields['privacy[view][wall]'] ?? '0',
      home: fields['privacy[view][home]'] ?? '0',
    );
  }

  /// 表单以 `action` 里的片段定位；找不到就退回第一个非搜索表单。
  static Element? _profileForm(Document doc, String actionHint) {
    final forms = doc.querySelectorAll('form');
    for (final form in forms) {
      final action = form.attributes['action'] ?? '';
      if (action.contains('search.php')) continue;
      if (action.contains(actionHint)) return form;
    }
    for (final form in forms) {
      if (!(form.attributes['action'] ?? '').contains('search.php')) return form;
    }
    return null;
  }

  /// 把表单里的控件读成 name → 当前值。select 取选中项，没标 selected 的取第一项，
  /// 这与浏览器提交默认值的行为一致。
  static Map<String, String> _formValues(Element? form) {
    final values = <String, String>{};
    if (form == null) return values;
    for (final el in form.querySelectorAll('input, textarea, select')) {
      final name = el.attributes['name'];
      if (name == null || name.isEmpty) continue;
      final type = (el.attributes['type'] ?? '').toLowerCase();
      if (type == 'submit' || type == 'button' || type == 'file' || type == 'reset') continue;
      if (el.localName == 'select') {
        final options = el.querySelectorAll('option');
        if (options.isEmpty) continue;
        final selected = options.where((o) => o.attributes.containsKey('selected')).toList();
        final pick = selected.isNotEmpty ? selected.first : options.first;
        values[name] = pick.attributes['value'] ?? pick.text.trim();
      } else if (el.localName == 'textarea') {
        values[name] = el.text;
      } else {
        values[name] = el.attributes['value'] ?? '';
      }
    }
    return values;
  }

  static Map<String, String> _privacyOf(Map<String, String> fields) {
    final privacy = <String, String>{};
    for (final entry in fields.entries) {
      final match = RegExp(r'^privacy\[([^\]]+)\]$').firstMatch(entry.key);
      if (match != null) privacy[match.group(1)!] = entry.value;
    }
    return privacy;
  }

  /// 居住地拆回省 / 市 / 区 / 街道。
  ///
  /// 站点保存的是四个独立字段，展示时拼成一行，中间没有分隔标记。直辖市的
  /// 市级字段本来就是空的，所以「天津市 大港区」要拆成 省=天津市、区=大港区，
  /// 不能想当然按 省/市 切。
  @visibleForTesting
  static (String province, String city, String dist, String community) splitRegion(String text) {
    final parts = text.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return ('', '', '', '');
    const municipalities = ['北京', '天津', '上海', '重庆', '香港', '澳门', '台湾'];
    final isMunicipality = municipalities.any((m) => parts.first.startsWith(m));
    if (isMunicipality) {
      return (
        parts[0],
        '',
        parts.length > 1 ? parts[1] : '',
        parts.length > 2 ? parts[2] : '',
      );
    }
    return (
      parts[0],
      parts.length > 1 ? parts[1] : '',
      parts.length > 2 ? parts[2] : '',
      parts.length > 3 ? parts[3] : '',
    );
  }

  Future<String> saveProfileBase(ProfileBaseSettings data) async {
    final region = splitRegion(data.resideText);
    final referer = AppConfig.uri(_profilePath('base')).toString();
    final response = await _http.post(
      'home.php',
      query: {'mod': 'spacecp', 'ac': 'profile', 'op': 'base', 'mobile': '2'},
      referer: referer,
      form: {
        'formhash': data.formhash,
        'occupation': data.occupation,
        'realname': data.realname,
        'gender': '${data.gender}',
        'birthyear': data.birthYear,
        'birthmonth': data.birthMonth,
        'birthday': data.birthDay,
        'resideprovince': region.$1,
        'residecity': region.$2,
        'residedist': region.$3,
        'residecommunity': region.$4,
        for (final entry in data.privacy.entries) 'privacy[${entry.key}]': entry.value,
        'profilesubmit': 'true',
      },
    );
    _ensureOk(response);
    final message = _pageMessage(parser.parse(response.body));
    if (message != null && _looksLikeError(message)) throw SiteException(message);

    // 站点会对部分字段做二次处理（比如真实姓名过滤字符），以回读结果为准。
    final saved = await fetchProfileBase();
    if (saved.realname != data.realname ||
        saved.occupation != data.occupation ||
        saved.gender != data.gender) {
      throw SiteException(message ?? '资料没有保存成功，请稍后重试');
    }
    return '资料已保存';
  }

  Future<String> saveProfileContact(ProfileContactSettings data) async {
    final referer = AppConfig.uri(_profilePath('contact')).toString();
    final response = await _http.post(
      'home.php',
      query: {'mod': 'spacecp', 'ac': 'profile', 'op': 'contact', 'mobile': '2'},
      referer: referer,
      form: {
        'formhash': data.formhash,
        'qq': data.qq,
        'mobile': data.mobile,
        for (final entry in data.privacy.entries) 'privacy[${entry.key}]': entry.value,
        'profilesubmit': 'true',
      },
    );
    _ensureOk(response);
    final message = _pageMessage(parser.parse(response.body));
    if (message != null && _looksLikeError(message)) throw SiteException(message);

    final saved = await fetchProfileContact();
    if (saved.qq != data.qq || saved.mobile != data.mobile) {
      throw SiteException(message ?? '联系方式没有保存成功，请稍后重试');
    }
    return '联系方式已保存';
  }

  Future<String> saveProfileInfo(ProfileInfoSettings data) async {
    final referer = AppConfig.uri(_profilePath('info')).toString();
    final response = await _http.post(
      'home.php',
      query: {'mod': 'spacecp', 'ac': 'profile', 'op': 'info', 'mobile': '2'},
      referer: referer,
      form: {
        'formhash': data.formhash,
        'bio': data.bio,
        'customstatus': data.customStatus,
        'sightml': data.signature,
        for (final entry in data.privacy.entries) 'privacy[${entry.key}]': entry.value,
        'profilesubmit': 'true',
      },
    );
    _ensureOk(response);
    final message = _pageMessage(parser.parse(response.body));
    if (message != null && _looksLikeError(message)) throw SiteException(message);

    final saved = await fetchProfileInfo();
    if (saved.customStatus.trim() != data.customStatus.trim() ||
        saved.signature.trim() != data.signature.trim()) {
      throw SiteException(message ?? '个人信息没有保存成功，请稍后重试');
    }
    return '个人信息已保存';
  }

  Future<String> savePrivacySettings(PrivacySettings data) async {
    final response = await _http.post(
      'home.php',
      query: {'mod': 'spacecp', 'ac': 'privacy', 'op': 'base', 'forcemobile': '1'},
      referer: AppConfig.uri('home.php?mod=spacecp&ac=privacy&forcemobile=1').toString(),
      form: {
        'formhash': data.formhash,
        'privacy[view][friend]': data.friend,
        'privacy[view][wall]': data.wall,
        'privacy[view][home]': data.home,
      },
    );
    _ensureOk(response);
    final message = _pageMessage(parser.parse(response.body));
    if (message != null && _looksLikeError(message)) throw SiteException(message);

    final saved = await fetchPrivacySettings();
    if (saved.friend != data.friend || saved.wall != data.wall || saved.home != data.home) {
      throw SiteException(message ?? '隐私设置没有保存成功，请稍后重试');
    }
    return '隐私设置已保存';
  }

  // ------------------------------------------------------------ 改名申请

  static const String _renamePlugin = 'nimba_rename';
  static const int _renameFallbackFee = 200;

  /// 改名申请页的校验串、扣费与当前用户名。
  ///
  /// 站点没把改名放进 spacecp，而是装了 `nimba_rename` 插件：PC 模板顶栏
  /// 的「改名申请」用 `showWindow` 弹表单，手机模板里根本没有这个入口，
  /// 所以固定按桌面页取。
  Future<RenameInfo> fetchRenameInfo() async {
    // App 的 UA 是移动端，Discuz 会直接给「手机版」提示页；`mobile=no` 配合
    // 桌面 UA 才能拿到真正的表单和扣费文案。
    final page = await _http.get(
      'plugin.php',
      query: {'id': _renamePlugin, 'mobile': 'no'},
      userAgent: _desktopUserAgent,
    );
    _ensureOk(page);
    final doc = parser.parse(page.body);
    final formhash = _findFormhash(page.body);
    if (formhash.isEmpty) throw SiteException('登录后才能申请改名');
    final text = _clean(doc.documentElement?.text ?? '');
    // 扣费写在表单下面的红字里，页面改价时这里跟着变。
    final fee = int.tryParse(RegExp(r'扣除\s*(\d+)\s*金币').firstMatch(text)?.group(1) ?? '') ??
        _renameFallbackFee;
    return RenameInfo(formhash: formhash, fee: fee);
  }

  /// 提交改名申请。扣金币由插件在服务端做，这里只负责把结果说清楚。
  Future<String> requestRename({
    required String newName,
    required String reason,
  }) async {
    final info = await fetchRenameInfo();
    final response = await _http.post(
      'plugin.php',
      query: {'id': _renamePlugin, 'mobile': 'no'},
      referer: AppConfig.uri('plugin.php', {'id': _renamePlugin, 'mobile': 'no'}).toString(),
      userAgent: _desktopUserAgent,
      form: {
        'formhash': info.formhash,
        'newname': newName,
        'reason': reason,
        'submit': 'true',
      },
    );
    _ensureOk(response);
    final message = renameMessage(response.body);
    if (renameFailed(message)) throw SiteException(message);
    return '改名申请已提交，等待管理员审核';
  }

  /// 插件回包里的提示语：可能是 `showmessage(...)` 脚本，也可能是提示页。
  @visibleForTesting
  static String renameMessage(String body) {
    final pageMessage = _pageMessage(parser.parse(body));
    if (pageMessage != null && pageMessage.trim().isNotEmpty) return pageMessage.trim();

    final cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true).firstMatch(body)?.group(1) ?? body;
    // 插件走的是 `showmessage('…');`，不是私信那套 succeedhandle。
    final call = RegExp(r'''(?:showmessage|succeedhandle|errorhandle)\s*\(\s*['"]([^'"]*)['"]''')
        .firstMatch(cdata);
    final quoted = _clean(call?.group(1) ?? '');
    if (quoted.isNotEmpty) return quoted;

    final text = _clean(cdata.replaceAll(RegExp(r'<[^>]+>'), ' '));
    return text.split(RegExp(r'[。！\n]')).first.trim();
  }

  /// 这次提交到底成没成。
  ///
  /// 成功文案本身就带「审核」二字，所以不能用通用的 `_looksLikeError`
  /// （它把「审核」算成错误）。先认成功词，再看失败词。
  @visibleForTesting
  static bool renameFailed(String message) {
    if (message.trim().isEmpty) return false;
    if (RegExp(r'(成功|已提交|已受理|等待审核|请等待审核)').hasMatch(message)) return false;
    return RegExp(
      r'(抱歉|失败|不能|无法|无权|权限|禁止|非法|敏感|不足|余额|已存在|已被|重名|重复|相同|长度|超过|至少|格式|不正确|未登录|请先登录)',
    ).hasMatch(message);
  }

  /// 我的等级：用户组、升级进度与权限表。
  Future<UserGroupInfo> fetchUserGroupInfo() async {
    final page = await _http.get(
      'home.php',
      query: {'mod': 'spacecp', 'ac': 'usergroup', 'mobile': '2'},
    );
    _ensureOk(page);
    final info = parseUserGroup(page.body);
    if (info == null) {
      throw SiteException(_pageMessage(parser.parse(page.body)) ?? '登录后才能查看等级');
    }
    return info;
  }

  /// 解析等级页。移动模板的结构比较稳定：头部 `.comiis_levhead` 放等级和
  /// 进度，下面 `.comiis_levshow table` 是两列权限表。
  @visibleForTesting
  static UserGroupInfo? parseUserGroup(String html) {
    final doc = parser.parse(html);
    final head = doc.querySelector('.comiis_levhead');
    if (head == null) return null;

    final name = _clean(head.querySelector('h2')?.text ?? '')
        .replaceFirst(RegExp(r'^我的等级[:：]\s*'), '');
    final levels = head
        .querySelectorAll('.lev_x em')
        .map((e) => _clean(e.text))
        .where((e) => e.isNotEmpty)
        .toList();

    var progress = 0.0;
    final barStyle = head.querySelector('.lev_x .z')?.attributes['style'] ?? '';
    final percent = RegExp(r'width:\s*([\d.]+)%').firstMatch(barStyle)?.group(1);
    if (percent != null) progress = (double.tryParse(percent) ?? 0) / 100;

    final hint = _clean(head.querySelector('h3')?.text ?? '');
    final upgrade = RegExp(r'还需要\s*(\d+)\s*积分升级到\s*(.+)').firstMatch(hint);

    var credits = '';
    final permissions = <GroupPermission>[];
    for (final tr in doc.querySelectorAll('.comiis_levshow table tr')) {
      final th = _clean(tr.querySelector('th')?.text ?? '');
      final td = tr.querySelector('td');
      if (th.isEmpty || td == null) continue;
      if (th == '积分') credits = _clean(td.text);
      // 这三行头部已经讲过了，表格里再列一遍只会显得啰嗦。
      if (th == '我的等级' || th == '积分' || th == '用户级别') continue;

      final icon = td.querySelector('i.comiis_font');
      if (icon != null && _clean(td.text).isEmpty) {
        // 字体图标没有文本：`f_g` 是灰色（无权），`f_wx` 是主题色（有权）。
        final classes = icon.attributes['class'] ?? '';
        permissions.add(GroupPermission(name: th, allowed: !classes.contains('f_g')));
      } else {
        permissions.add(GroupPermission(name: th, value: _clean(td.text)));
      }
    }

    final rawAvatar = head.querySelector('.user_img img')?.attributes['src'] ?? '';
    return UserGroupInfo(
      name: name,
      level: levels.isNotEmpty ? levels[0] : '',
      nextLevel: levels.length > 1 ? levels[1] : '',
      nextName: upgrade?.group(2)?.trim() ?? '',
      credits: credits,
      remaining: int.tryParse(upgrade?.group(1) ?? '') ?? 0,
      progress: progress.clamp(0.0, 1.0),
      avatar: rawAvatar.startsWith('//') ? 'https:$rawAvatar' : rawAvatar,
      permissions: permissions,
    );
  }

  Future<ComposeInfo> fetchComposeInfo(int fid) async {
    final page = await _http.get(
      'forum.php',
      query: {'mod': 'post', 'action': 'newthread', 'fid': '$fid', 'mobile': '2'},
    );
    _ensureOk(page);
    final formhash = _findFormhash(page.body);
    if (formhash.isEmpty) {
      throw SiteException(_pageMessage(parser.parse(page.body)) ?? '请先登录后再发帖');
    }
    var uploadHash = findUploadHash(page.body);
    var uid = findUploadUid(page.body);
    var source = '手机版';
    if (uploadHash.isEmpty || uid <= 0) {
      // 手机模板（含 comiis 这类改版）走的是表单直传：发帖表单里直接放
      // `<input type="file" name="Filedata">`，页面根本不输出 swfupload 的 hash。
      // 桌面模板会输出 `post_params: {"uid" : "34273", "hash":"..."}`，
      // 所以改去桌面版页面拿一份。
      for (final query in <Map<String, String>>[
        {'mod': 'post', 'action': 'newthread', 'fid': '$fid', 'mobile': 'no'},
        {'mod': 'post', 'action': 'newthread', 'fid': '$fid', 'mobile': '2', 'inajax': '1'},
      ]) {
        try {
          final extra = await _http.get('forum.php', query: query);
          if (extra.statusCode != 200) continue;
          final hash = findUploadHash(extra.body);
          if (uploadHash.isEmpty && hash.isNotEmpty) {
            uploadHash = hash;
            source = query['mobile'] == 'no' ? '桌面版' : 'ajax版';
          }
          if (uid <= 0) uid = findUploadUid(extra.body);
          if (uploadHash.isNotEmpty && uid > 0) break;
        } catch (_) {
          // 兜底请求失败不影响发文字帖。
        }
      }
    }
    return ComposeInfo(
      formhash: formhash,
      uploadHash: uploadHash,
      uid: uid,
      debug: '手机版 ${page.body.length}B，hash='
          '${uploadHash.isEmpty ? '无' : '${uploadHash.length}位($source)'}，uid=$uid',
    );
  }

  /// 上传图片 / 附件，返回服务器分配的 aid，用于 `[attachimg]aid[/attachimg]`。
  Future<int> uploadAttachment({
    required List<int> bytes,
    required String filename,
    required String uploadHash,
    required int uid,
    required String referer,
    bool image = true,
    int? fid,
  }) async {
    if (uid <= 0 || uploadHash.isEmpty) {
      // 服务端校验 `hash == md5(salt + uid)`，缺一个必定 exit() 成空白响应。
      // 与其发出去挨一个看不懂的失败，不如把话说清楚，让调用方重拉发帖页。
      throw SiteException(
        uid <= 0 ? '没取到账号 ID，退出发帖页重新进入再试' : '没取到上传凭证，退出发帖页重新进入再试',
      );
    }
    final result = await _http.postFile(
      'misc.php',
      query: {
        'mod': 'swfupload',
        // 桌面版模板的上传地址带这一段，缺了会落到别的 operation 分支。
        'action': 'swfupload',
        'operation': 'upload',
        'type': image ? 'image' : 'attach',
        if (fid != null && fid > 0) 'fid': '$fid',
        // 关键：forum_upload 类校验的是 $_GET['uid'] / $_GET['hash']，
        // 只放在 POST 里会直接判成「非法操作」（错误码 10）。
        'uid': '$uid',
        'hash': uploadHash,
        // simple=2 才输出 DISCUZUPLOAD|type|error|aid|... 的 8 段格式，
        // 不传就只剩一个裸数字，解析不了。
        'simple': '2',
        'inajax': 'yes',
        'infloat': 'yes',
      },
      field: 'Filedata',
      filename: filename,
      bytes: bytes,
      fields: {'uid': '$uid', 'hash': uploadHash, if (fid != null && fid > 0) 'fid': '$fid'},
      referer: referer,
    );
    final parsed = parseUploadResult(result.body);
    if (parsed == null) {
      final msg = _pageMessage(parser.parse(result.body));
      // 服务端不认凭证时会直接 exit()，响应是空的。把发出去的关键值带出来，
      // 用户截图就能分清是「没取到 hash」还是「取到但不对」。
      throw SiteException(
        '${msg ?? '服务器没接受这个上传凭证'}（hash ${uploadHash.length} 位，uid $uid）',
      );
    }
    if (!parsed.ok) {
      throw SiteException(_uploadMessage(parsed.errorCode));
    }
    return parsed.aid;
  }

  /// 页面中收藏 / 取消收藏的原始链接（已收藏时 Discuz 会输出 op=delete&favid=xx）。
  String _favoriteHref(String html) {
    final matches = RegExp(
      'href=[\'"]([^\'"]*ac=favorite[^\'"]*)[\'"]',
      caseSensitive: false,
    ).allMatches(html);
    var first = '';
    for (final match in matches) {
      final href = match.group(1) ?? '';
      if (href.isEmpty) continue;
      if (first.isEmpty) first = href;
      if (href.contains('op=delete')) return _absolute(href);
    }
    return first.isEmpty ? '' : _absolute(first);
  }

  /// 是否已收藏：优先看 op=delete 链接，其次看收藏图标的 f_a 状态。
  bool _isThreadFavorited(String html) {
    if (_favoriteHref(html).contains('op=delete')) return true;
    return RegExp(r'comiis_favorite_a_color[^"]*\bf_a\b').hasMatch(html);
  }

  /// 页面上「赞」按钮的链接（原样，可能是相对路径）。
  ///
  /// 这里必须找 `<a>`，不能找 `#recommendv_add`：Discuz 原生模板里
  /// `#recommendv_add` 是**显示数字的那个节点**，按钮是它前面的一颗链接。
  /// 之前拿数字节点判断激活态，等于一直在看一个 span 的 class，自然永远读不到
  /// 「已赞」，退出重进就回到未赞。
  ///
  /// 踩（do=subtract）要排除，否则会把踩的链接当成赞的。
  @visibleForTesting
  static String recommendHref(Document doc) {
    String? fallback;
    for (final link in doc.querySelectorAll('a[href]')) {
      final href = (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
      if (href.isEmpty) continue;
      if (!href.contains('action=recommend') && !href.contains('do=cancel')) continue;
      if (href.contains('do=subtract')) continue;
      final cls = link.attributes['class'] ?? '';
      final text = link.text.trim();
      if (text.contains('赞') || cls.contains('comiis_recommend_a')) return href;
      fallback ??= href;
    }
    return fallback ?? '';
  }

  /// 当前账号是否已赞过该主题。
  ///
  /// Discuz 的 recommend 没有「查询」接口，只能读页面上按钮的链接：已赞时
  /// 模板会把 `do=add` 换成取消动作（`do=cancel` 或 `cancel=1`），或者给按钮
  /// 加激活类。链接优先，类名兜底。
  @visibleForTesting
  static bool threadLiked(Document doc) {
    final href = recommendHref(doc);
    if (href.isNotEmpty) {
      if (RegExp(r'do=(cancel|del|delete|remove|unrecommend)', caseSensitive: false).hasMatch(href)) {
        return true;
      }
      if (RegExp(r'[?&](?:cancel|cancle)=1').hasMatch(href)) return true;
    }
    for (final button in doc.querySelectorAll('a.comiis_recommend_a_color, a[href*="action=recommend"]')) {
      final cls = button.attributes['class'] ?? '';
      if (RegExp(r'(?:^|\s)(?:f_a|on|active|selected)(?:\s|$)').hasMatch(cls)) return true;
    }
    final html = doc.documentElement?.outerHtml ?? '';
    // 站点在用的克米手机模板：点赞图标是
    // `<i class="comiis_font comiis_recommend_color f_a">`，取消后换回 f_b。
    // 它既不是链接、也不叫 `comiis_recommend_a_color`（那是收藏），所以只按
    // 旧的两条找，永远是「未赞」——进帖子看到空心，点一下发 add，服务端回
    // 「已评价过」，取消更是无从谈起。
    if (RegExp(r'comiis_recommend_color[^"]*\bf_a\b').hasMatch(html)) return true;
    // 同一套激活类，有的模板把 f_a 加在按钮外层。
    return RegExp(r'comiis_recommend_a_color[^"]*\bf_a\b').hasMatch(html);
  }

  /// 点赞 / 踩。Discuz 的 recommend 接口要求 inajax=1，返回 CDATA 包裹的提示。
  ///
  /// [cancelHref] 是帖子页上「已赞」按钮自带的链接。取消动作各家模板不一样
  /// （`do=cancel`、`cancel=1`、甚至换成了插件地址），自己拼参数只能靠猜；
  /// 页面既然把取消地址写出来了，就先用它。
  Future<void> recommend({
    required int tid,
    required String formhash,
    required bool up,
    bool cancel = false,
    String cancelHref = '',
  }) async {
    if (formhash.isEmpty) throw SiteException('操作凭证已失效，请下拉刷新后重试');
    final query = <String, String>{
      'mod': 'misc',
      'action': 'recommend',
      'do': cancel ? 'cancel' : (up ? 'add' : 'subtract'),
      'tid': '$tid',
      'hash': formhash,
      'inajax': '1',
      'mobile': '2',
    };

    if (!cancel) {
      final result = await _http.get(
        'forum.php',
        query: query,
        referer: _threadReferer(tid),
      );
      _ensureOk(result);
      final failure = recommendFailure(_inajaxMessage(result.body), up: up);
      if (failure != null) throw SiteException(failure);
      return;
    }

    await _cancelRecommend(tid: tid, formhash: formhash, cancelHref: cancelHref);
  }

  /// 上一次确认有效的取消动作。试对一次就记住，下次直接用，省掉一轮试探。
  static String? _workingCancelAction;

  /// 取消动作的候选。Discuz 原生只有 add / subtract，取消是模板自己加的，
  /// 动作名各家不同（cancel / del / unrecommend / delete），挨个试。
  static const List<String> _cancelActions = <String>['cancel', 'del', 'unrecommend', 'delete'];

  /// 站点自己的取消入口。
  ///
  /// 赞走的是 Discuz 的 recommend，取消却不在 Discuz 里：克米模板的 JS 在收到
  /// 「您已评价过本主题」之后，改调这个插件动作，回 `ok`，并把图标从 f_a 换回
  /// f_b。原生 Discuz 只有 add / subtract，所以此前挨个试 cancel / del /
  /// unrecommend / delete 全是空转，服务端一次也没真的删过。
  String _pluginCancelUrl(int tid) =>
      'plugin.php?id=comiis_app&comiis=re_recommend&tid=$tid&inajax=1';

  /// 取消点赞。
  ///
  /// 判定只看页面状态：这个模板取消之后「赞数」并不回落（实测取消前后都是 2），
  /// 拿数字当证据会把成功判成失败；而它对不认识的动作也回 200，空回执会被当成
  /// 成功。唯一靠得住的是重新拉一次帖子页，看图标还是不是 f_a。
  Future<void> _cancelRecommend({
    required int tid,
    required String formhash,
    required String cancelHref,
  }) async {
    final referer = _threadReferer(tid);
    String? lastFailure;

    Future<bool> settle(Future<HttpResult> Function() send) async {
      try {
        final result = await send();
        _ensureOk(result);
        final message = _inajaxMessage(result.body);
        final failure = recommendFailure(message, up: true);
        if (failure != null) {
          lastFailure = failure;
          return false;
        }
        final liked = await fetchLikedState(tid);
        // 页面拉不下来就只能信回执（ok / 空串都是站点认了这次请求）。
        if (liked == null) return true;
        if (!liked) return true;
        lastFailure = '取消失败：站点未移除这条赞';
        return false;
      } catch (error) {
        lastFailure = error is SiteException ? error.message : '取消请求未送达';
        return false;
      }
    }

    // 模板自己的取消动作，先打它。
    if (await settle(() => _http.get(_pluginCancelUrl(tid), referer: referer))) return;

    // 页面自己给出的取消地址次之。
    if (_looksLikeCancelHref(cancelHref)) {
      if (await settle(() => _http.get(cancelHref, referer: referer))) return;
    }

    final actions = <String>[
      if (_workingCancelAction != null) _workingCancelAction!,
      ..._cancelActions,
    ];
    for (final action in actions) {
      final query = <String, String>{
        'mod': 'misc',
        'action': 'recommend',
        'do': action,
        'tid': '$tid',
        'hash': formhash,
        'inajax': '1',
        'mobile': '2',
      };
      // 先 POST：模板改写过的 handler 通常用 checkformhash()，只认表单里的
      // formhash，只带 hash 会被判「请求来路不正确」。
      final posted = await settle(
        () => _http.post(
          'forum.php',
          query: query,
          form: <String, String>{
            'formhash': formhash,
            'tid': '$tid',
            'handlekey': 'recommend',
            'inajax': '1',
          },
          referer: referer,
        ),
      );
      if (posted) {
        _workingCancelAction = action;
        return;
      }
      final got = await settle(
        () => _http.get(
          'forum.php',
          query: <String, String>{...query, 'formhash': formhash},
          referer: referer,
        ),
      );
      if (got) {
        _workingCancelAction = action;
        return;
      }
    }
    throw SiteException(lastFailure ?? '取消失败，站点没有接受任何一种取消方式');
  }

  /// 重新拉一次帖子页，读「已赞」标记；页面拉不下来返回 null。
  ///
  /// 取消和点赞都拿它当裁判：Discuz 没有「我赞没赞」的查询接口，模板的回执
  /// 文案又各不相同，只有页面上的 f_a / f_b 是硬证据。
  Future<bool?> fetchLikedState(int tid) async {
    try {
      final result = await _http.get(
        'forum.php',
        query: <String, String>{
          'mod': 'viewthread',
          'tid': '$tid',
          'mobile': '2',
          'page': '1',
        },
        referer: _threadReferer(tid),
      );
      if (result.statusCode != 200) return null;
      return threadLiked(parser.parse(result.body));
    } catch (_) {
      return null;
    }
  }

  /// 只取主题页上的「赞」数字，给界面显示用。
  ///
  /// 别拿它判断取消有没有生效：克米模板取消之后这个数字不会回落（实测请求前后
  /// 都是 2），判断状态一律走 [fetchLikedState]。取不到时返回 null。
  Future<int?> fetchLikeCount(int tid) async {
    try {
      final result = await _http.get(
        'forum.php',
        query: <String, String>{
          'mod': 'viewthread',
          'tid': '$tid',
          'mobile': '2',
          'page': '1',
        },
        referer: _threadReferer(tid),
      );
      if (result.statusCode != 200) return null;
      final doc = parser.parse(result.body);
      final node = doc.querySelector('.comiis_recommend_num') ??
          doc.querySelector('#recommendv_add');
      final digits = RegExp(r'\d+').firstMatch(_clean(node?.text ?? ''))?.group(0);
      return digits == null ? null : int.tryParse(digits);
    } catch (_) {
      return null;
    }
  }

  /// 页面上的链接是不是「取消赞」。只认明确的取消动作，别把 `do=add`
  /// 当成取消地址再打一遍。
  static bool _looksLikeCancelHref(String href) {
    if (href.isEmpty) return false;
    if (RegExp(r'do=(?:cancel|del|delete|remove|unrecommend)', caseSensitive: false).hasMatch(href)) {
      return true;
    }
    return RegExp(r'[?&](?:cancel|cancle)=1').hasMatch(href);
  }

  /// 判别 recommend 的回执：返回 null 表示成功，否则是给用户看的错误文案。
  ///
  /// 原来用白名单匹配「点赞成功」「感谢」这些词，站点模板一换文案就会误判：
  /// 明明赞上了却提示「点赞失败」，而调用方因此没有置位「已赞」，用户再点
  /// 仍然是 add，永远走不到取消。这里反过来只认明确的失败，其余当成功。
  @visibleForTesting
  static String? recommendFailure(String message, {bool up = true}) {
    // 有的模板只回一段 script，CDATA 里没有中文，取出来是空串——这是成功。
    if (message.isEmpty) return null;
    final already = up ? '你已经赞过这个帖子' : '你已经踩过这个帖子';
    final failures = <String, String>{
      '已评价过': already,
      '已经评价': already,
      '已经赞过': already,
      '不能评价自己': '不能点赞自己的帖子',
      '自己的帖子': '不能点赞自己的帖子',
      '已关闭': '该主题已关闭，无法点赞',
      '评价机会已用完': '今天的点赞次数已用完',
      '还没有评价': '你还没有点赞',
      '没有权限': '没有权限执行该操作',
      '无权': '没有权限执行该操作',
      '非法操作': '操作被站点拒绝，请稍后重试',
      '来路不正确': '站点校验未通过，请重试',
      '表单无法提交': '站点校验未通过，请重试',
      '未定义操作': '站点不支持取消点赞',
      'undefined_action': '站点不支持取消点赞',
      '未登录': '登录状态已失效，请重新登录',
      '请先登录': '登录状态已失效，请重新登录',
      '主题不存在': '主题不存在或已被删除',
    };
    for (final entry in failures.entries) {
      if (message.contains(entry.key)) return entry.value;
    }
    // 取消要比点赞严：站点不认这个动作时常常回 200 + 一句没见过的提示，
    // 宽松放行会让界面显示「已取消」、服务端却仍然赞着，重进又亮。
    if (!up &&
        !message.contains('成功') &&
        !message.contains('已取消') &&
        !message.contains('完成')) {
      final brief = message.length > 50 ? '${message.substring(0, 50)}…' : message;
      return '取消失败：$brief';
    }
    return null;
  }

  /// 供测试直接验证 inajax 回执的取文案逻辑。
  @visibleForTesting
  static String inajaxMessage(String body) => _inajaxMessage(body);

  /// 读取 inajax 响应里的提示文案。
  ///
  /// Discuz 的成功响应是一段脚本，而不是一段文字：
  ///
  /// ```html
  /// <root><![CDATA[<script type="text/javascript" reload="1">if(typeof
  /// succeedhandle_mods=='function') {succeedhandle_mods('forum.php?...',
  /// '管理操作成功','');} setTimeout(...);</script>]]></root>
  /// ```
  ///
  /// 早先只是把标签去掉，于是整段 JS 被当成提示弹了出来。这里先从脚本参数
  /// 里取那句中文提示，取不到再把脚本/样式剔掉读正文。
  static String _inajaxMessage(String body) {
    final cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true).firstMatch(body)?.group(1) ?? body;
    final call = RegExp(r'succeedhandle_\w+\s*\((.{0,600}?)\)\s*;', dotAll: true).firstMatch(cdata);
    if (call != null) {
      final quoted = RegExp(r'''['"]([^'"]*)['"]''')
          .allMatches(call.group(1)!)
          .map((match) => match.group(1) ?? '')
          .where((text) => RegExp(r'[\u4e00-\u9fa5]').hasMatch(text))
          .toList();
      if (quoted.isNotEmpty) return _clean(quoted.first);
    }
    final text = cdata
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    return _clean(text);
  }

  /// 参与投票。`ids` 为选项 id，多选时逐个提交。
  Future<String> votePoll({
    required int tid,
    required int fid,
    required String formhash,
    required List<int> ids,
  }) async {
    if (ids.isEmpty) throw SiteException('请选择投票选项');
    if (formhash.isEmpty) throw SiteException('投票凭证已失效，请下拉刷新后重试');
    final form = <String, String>{
      'formhash': formhash,
      'pollsubmit': 'yes',
      'quickforward': 'yes',
      'handlekey': 'poll',
    };
    for (var i = 0; i < ids.length; i++) {
      form['pollanswers[$i]'] = '${ids[i]}';
    }
    final response = await _http.post(
      'forum.php',
      query: {
        'mod': 'misc',
        'action': 'votepoll',
        'tid': '$tid',
        'fid': '$fid',
        'mobile': '2',
      },
      referer: _threadReferer(tid),
      form: form,
    );
    final msg = _pageMessage(parser.parse(response.body));
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    return msg ?? '投票成功';
  }

  /// 打开「编辑本帖」表单，取回原标题与正文原文。
  ///
  /// 编辑是整篇覆盖：`message` 交了什么都原样存进去，缺了就把整楼清空。
  /// 所以改写之前必须先读一遍原文，而正文在帖子页里已经是渲染后的 HTML，
  /// BBCode 回不去，只能来这里拿 textarea 里的原稿。
  ///
  /// 手机模板个别主题不渲染编辑表单，回落到桌面版再试一次；
  /// 两次都拿不到就认为没有编辑权限（或帖子已关闭编辑）。
  Future<({String subject, String message, String formhash})> fetchEditDraft({
    required int tid,
    required int pid,
    required int fid,
  }) async {
    String? lastMessage;
    for (final query in <Map<String, String>>[
      {
        'mod': 'post',
        'action': 'edit',
        'fid': '$fid',
        'tid': '$tid',
        'pid': '$pid',
        'mobile': '2',
      },
      {
        'mod': 'post',
        'action': 'edit',
        'fid': '$fid',
        'tid': '$tid',
        'pid': '$pid',
      },
    ]) {
      final page = await _http.get('forum.php', query: query, referer: _threadReferer(tid));
      _ensureOk(page);
      final doc = parser.parse(page.body);
      final textarea = doc.querySelector('textarea[name="message"]');
      final message = (textarea?.text ?? '').trim();
      if (message.isEmpty) {
        lastMessage = _pageMessage(doc);
        continue;
      }
      final subjectInput = doc.querySelector('input[name="subject"]');
      final subject = (subjectInput?.attributes['value'] ?? '').trim();
      return (
        subject: subject,
        message: message,
        formhash: _findFormhash(page.body),
      );
    }
    throw SiteException(
      lastMessage != null && lastMessage.isNotEmpty
          ? lastMessage
          : '打不开编辑页：可能没有编辑权限，或楼主已关闭编辑',
    );
  }

  /// 编辑自己的帖子 / 回复。
  Future<String> editPost({
    required int fid,
    required int tid,
    required int pid,
    required String subject,
    required String message,
    required String formhash,
  }) async {
    final response = await _http.post(
      'forum.php',
      query: {
        'mod': 'post',
        'action': 'edit',
        'fid': '$fid',
        'tid': '$tid',
        'pid': '$pid',
        'editsubmit': 'yes',
        'mobile': '2',
      },
      referer: _threadReferer(tid),
      form: {
        'formhash': formhash,
        'subject': subject,
        'message': message,
        'posttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
        'usesig': '1',
        'save': '',
      },
    );
    // 保存成功后服务端 302 回帖子页：落点就是 viewthread，直接算成功。
    // 那个页面上有一条「本帖最后由 xxx 于 … 编辑 …」的记录，若继续按「页面消息」
    // 解析，会因为它引用了正文里的「登录」「审核」之类的字眼被判成错误。
    if (_landedOnThread(response)) return '编辑成功';
    final msg = _pageMessage(parser.parse(response.body)) ?? '';
    if (_looksLikeError(msg)) throw SiteException(msg);
    // 还停在编辑页又没有明确的成功提示，就是没提交上去。早先这里直接
    // 返回「编辑成功」，服务端把表单退回来（凭证过期、被拦截）时用户会
    // 以为已经改好，回头一看正文根本没变。
    if (_editAccepted.hasMatch(msg)) return '编辑成功';
    throw SiteException(msg.isNotEmpty ? msg : '保存未生效，请稍后重试或到网页端修改');
  }

  static final RegExp _editAccepted = RegExp(r'(编辑成功|保存成功|修改成功)');

  /// 请求最终落在帖子页（`mod=viewthread`），说明提交被服务端接受了。
  bool _landedOnThread(HttpResult response) {
    final uri = response.uri.toString();
    return uri.contains('mod=viewthread') || uri.contains('thread-');
  }

  /// 删除自己的帖子 / 回复。
  /// 删除自己的回复或主题。
  ///
  /// Discuz 没有独立删帖接口：网页端「删除本帖」就是编辑页带上 `delete=1`
  /// 提交（`forum.php?mod=post&action=edit&...&delete=1`，POST + `formhash` +
  /// `editsubmit=yes`）。早先打的 `mod=misc&action=postdelete` 在 X3.5 里
  /// 根本不存在，服务端只会把页面再渲染一遍，主题原样留着。
  /// 站点若关闭「编辑帖子时允许删除帖子」，服务端会回「不允许删除帖子」。
  Future<String> deletePost({
    required int fid,
    required int tid,
    required int pid,
    required String formhash,
    int page = 1,
  }) async {
    final request = deleteRequest(fid: fid, tid: tid, pid: pid, formhash: formhash, page: page);
    final response = await _http.post(
      'forum.php',
      query: request.query,
      form: request.form,
      referer: _threadReferer(tid),
    );
    final message = _pageMessage(parser.parse(response.body));
    final failure = deleteFailure(
      finalUrl: response.uri.toString(),
      body: response.body,
      pid: pid,
      message: message,
    );
    if (failure != null) throw SiteException(failure);
    return '删除成功';
  }

  /// 删除到底成没成。
  ///
  /// 光看提示语不够：站点常在帖子页挂一条「感谢分享」之类的公告，
  /// 早先只要没读到拒绝语就当成功，删不掉也会提示成功；
  /// 反过来只看「刷新后这楼还在」又会被一次刷新失败冤枉。
  /// 这里按三个硬信号判断：
  /// 1. 提示语里出现拒绝字样；
  /// 2. 地址还停在编辑页（`action=edit`）——服务端把表单原样退回来了；
  /// 3. 落在帖子页但这一楼的节点还在。
  @visibleForTesting
  static String? deleteFailure({
    required String finalUrl,
    required String body,
    required int pid,
    String? message,
  }) {
    final text = (message ?? '').trim();
    if (text.isNotEmpty && _deleteRejected.hasMatch(text)) return text;
    const fallback = '删除未生效，请稍后重试或到网页端删除';
    if (finalUrl.contains('action=edit')) {
      return text.isNotEmpty ? text : fallback;
    }
    if (pid > 0 && _mentionsPost(body, pid)) {
      return text.isNotEmpty ? text : fallback;
    }
    return null;
  }

  /// 页面里还能不能找到这一楼。
  ///
  /// 只认楼层容器的 id，不认 `pid=` 参数：别的楼层引用它时也会出现 pid，
  /// 那样删成功反而会被判成失败。
  static bool _mentionsPost(String html, int pid) =>
      html.contains('id="post_$pid"') ||
      html.contains("id='post_$pid'") ||
      html.contains('id="pid$pid"') ||
      html.contains("id='pid$pid'") ||
      html.contains('id="postmessage_$pid"') ||
      html.contains("id='postmessage_$pid'");

  static final RegExp _deleteRejected =
      RegExp(r'(不允许|没有权限|无权|抱歉|失败|无效|来路不正确|审核|不存在|已关闭|不能删除)');

  /// 组装删帖请求。单独抽出来是为了让测试盯住契约：
  /// Discuz 的删帖是「编辑页 + delete=1」，不是不存在的 `action=postdelete`。
  static ({Map<String, String> query, Map<String, String> form}) deleteRequest({
    required int fid,
    required int tid,
    required int pid,
    required String formhash,
    int page = 1,
  }) =>
      (
        query: {
          'mod': 'post',
          'action': 'edit',
          'fid': '$fid',
          'tid': '$tid',
          'pid': '$pid',
          'page': '$page',
          'delete': '1',
          'mobile': '2',
        },
        form: {
          'formhash': formhash,
          'editsubmit': 'yes',
          'delete': '1',
        },
      );

  /// 网页端举报面板给出的理由，顺序与站点一致。
  static const List<String> reportReasons = ['广告垃圾', '违规内容', '重复发帖', '恶意灌水', '其他'];

  /// 举报主题或回复。
  ///
  /// 网页端的举报入口是 `misc.php?mod=report`（不是 `forum.php?mod=misc&action=report`）：
  /// 必须用 `rtype=post&rid=pid` 指明举报对象、带 `inajax=1`，否则模块开头就直接
  /// `showmessage('report_parameters_invalid')`；`reportsubmit` 也只能放在 POST 体里，
  /// 因为 `submitcheck()` 见到 GET 提交会直接返回 false，服务端只会把空表单再渲染一遍，
  /// 举报永远不会写进 `common_report` 表。
  /// Discuz 没有“理由编号”，只有一段 `message` 文本，所以选中的理由要拼进去。
  Future<String> report({
    required int fid,
    required int tid,
    required int pid,
    required String formhash,
    required String reason,
    String message = '',
  }) async {
    final request = reportRequest(
      fid: fid,
      tid: tid,
      pid: pid,
      formhash: formhash,
      reason: reason,
      message: message,
    );
    final response = await _http.post(
      'misc.php',
      query: request.query,
      form: request.form,
      referer: _threadReferer(tid),
    );
    _ensureOk(response);
    final reply = reportReplyText(response.body);
    if (_reportAccepted.hasMatch(reply)) return '举报已提交';
    throw SiteException(reply.isNotEmpty ? reply : '站点没有返回受理结果，请稍后重试或到网页端举报');
  }

  /// 组装举报请求（地址参数与表单字段）。
  ///
  /// 单独抽出来是为了让测试盯住契约：`reportsubmit` 一旦被挪到 query 上，
  /// 服务端的 `submitcheck()` 会直接判为未提交，举报不会入库。
  static ({Map<String, String> query, Map<String, String> form}) reportRequest({
    required int fid,
    required int tid,
    required int pid,
    required String formhash,
    required String reason,
    String message = '',
  }) {
    final note = message.trim();
    final text = note.isEmpty ? reason : '$reason｜$note';
    final target = AppConfig.uri('forum.php', {
      'mod': 'redirect',
      'goto': 'findpost',
      'ptid': '$tid',
      'pid': '$pid',
    }).toString();
    return (
      query: {
        'mod': 'report',
        'rtype': 'post',
        'rid': '$pid',
        'tid': '$tid',
        'fid': '$fid',
        'inajax': '1',
        'handlekey': 'report',
        'ajaxdata': 'json',
      },
      form: {
        'formhash': formhash,
        'reportsubmit': 'true',
        'rtype': 'post',
        'rid': '$pid',
        'tid': '$tid',
        'fid': '$fid',
        'url': base64Encode(utf8.encode(target)),
        'inajax': '1',
        'handlekey': 'report',
        'message': text,
      },
    );
  }

  static final RegExp _reportAccepted = RegExp(r'(举报成功|举报已经成功|感谢.{0,6}举报|report_succeed)');

  /// 从 `misc.php?mod=report` 的返回体里取出站点提示。
  ///
  /// 带 `ajaxdata=json` 时是 `{"message":"举报成功"}`；不带时是
  /// `<root><![CDATA[举报成功]]></root>`；再退一步按普通页面解析。
  static String reportReplyText(String body) {
    final raw = body.trim();
    if (raw.startsWith('{')) {
      try {
        final data = jsonDecode(raw);
        if (data is Map) {
          final message = '${data['message'] ?? ''}'.trim();
          if (message.isNotEmpty) return _clean(parser.parseFragment(message).text ?? '');
        }
      } catch (_) {
        // 不是合法 JSON，落到下面的 XML / 页面解析。
      }
    }
    final cdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(body);
    if (cdata != null) {
      final message = _clean(parser.parseFragment(cdata.group(1)!).text ?? '');
      if (message.isNotEmpty) return message;
    }
    final doc = parser.parse(body);
    final message = _pageMessage(doc);
    if (message != null) return message;
    final text = _clean(doc.body?.text ?? '');
    return text.length > 200 ? text.substring(0, 200) : text;
  }

  /// 读取当前用户组可用的打赏项（好评 / 金币等）、单次范围与今日剩余额度。
  ///
  /// 评分弹窗由站点按用户组动态生成，这里直接解析 `showratetip` 试读页；
  /// 站点下拉（`#scoreoption*`）已按 24 小时剩余额度裁剪，是最准确的来源。
  Future<RateOptions> fetchRateOptions({required int tid, required int pid}) async {
    try {
      final result = await _http.get(
        'forum.php',
        query: {
          'mod': 'misc',
          'action': 'rate',
          'tid': '$tid',
          'pid': '$pid',
          'showratetip': '1',
          'mobile': '2',
        },
        referer: _threadReferer(tid),
      );
      _ensureOk(result);
      final doc = parser.parse(result.body);
      final fields = <RateField>[];
      final seen = <int>{};
      for (final control in doc.querySelectorAll('input[name^="score"], select[name^="score"]')) {
        final name = control.attributes['name'] ?? '';
        final id = int.tryParse(name.replaceFirst('score', '')) ?? 0;
        if (id <= 0 || !seen.add(id)) continue;

        // 站点给出的可选分值，已按 24 小时剩余额度裁剪。
        final presets = <int>[];
        if (control.localName == 'select') {
          for (final option in control.querySelectorAll('option')) {
            final value = int.tryParse(
              _clean(option.attributes['value'] ?? option.text).replaceAll('+', ''),
            );
            if (value != null && !presets.contains(value)) presets.add(value);
          }
        } else {
          for (final item in doc.querySelectorAll('#scoreoption$id li')) {
            final value = int.tryParse(_clean(item.text).replaceAll('+', ''));
            if (value != null && !presets.contains(value)) presets.add(value);
          }
        }
        presets.sort();

        Element? row;
        for (final candidate in doc.querySelectorAll('tr')) {
          if (candidate.querySelector('[name="$name"]') != null) {
            row = candidate;
            break;
          }
        }

        final text = _clean(row?.text ?? control.parent?.text ?? '');
        final range = RegExp(r'(-?\d+)\s*~\s*(-?\d+)').firstMatch(text);
        var min = int.tryParse(range?.group(1) ?? '') ?? 0;
        var max = int.tryParse(range?.group(2) ?? '') ?? 1;
        if (presets.isNotEmpty) {
          min = presets.first;
          max = presets.last;
        }
        if (max < min) max = min;
        if (max > 100) max = 100;

        // 评分表第 4 列为「今日剩余」；部分模板只在文案里给出。
        final cells = row?.querySelectorAll('td') ?? const <Element>[];
        var left = max;
        final leftMatch = RegExp(r'剩余\s*[:：]?\s*(\d+)').firstMatch(text);
        if (leftMatch != null) {
          left = int.tryParse(leftMatch.group(1) ?? '') ?? max;
        } else if (cells.length >= 4) {
          left = int.tryParse(
                RegExp(r'\d+').firstMatch(_clean(cells[3].text))?.group(1) ?? '',
              ) ??
              max;
        }
        if (left < 0) left = 0;

        final labelSource = row != null && row.children.isNotEmpty
            ? row.children.first.text
            : (control.parent?.text ?? '');
        var label = _clean(labelSource).replaceAll(RegExp(r'[0-9\s]'), '');
        if (label.isEmpty || label.length > 8) label = '积分 $id';

        fields.add(RateField(
          id: id,
          label: label,
          min: min,
          max: max,
          left: left,
          presets: presets,
        ));
      }
      if (fields.isEmpty) {
        final notice = _rateNotice(result.body);
        if (notice.isNotEmpty) {
          return RateOptions(fields: RateOptions.fallback.fields, notice: notice);
        }
        return RateOptions.fallback;
      }
      return RateOptions(
        fields: fields,
        canNotify: doc.querySelector('input[name="sendreasonpm"]') != null,
      );
    } catch (_) {
      return RateOptions.fallback;
    }
  }

  /// 给某个楼层打赏（Discuz `misc&action=rate`）。
  Future<String> rate({
    required int tid,
    required int pid,
    required String formhash,
    required Map<int, int> scores,
    String reason = '',
    bool notify = false,
  }) async {
    final response = await _http.post(
      'forum.php',
      query: {
        'mod': 'misc',
        'action': 'rate',
        'tid': '$tid',
        'pid': '$pid',
        'ratesubmit': 'yes',
        'handlekey': 'rate',
        'formhash': formhash,
        'inajax': '1',
        'mobile': '2',
      },
      referer: _threadReferer(tid),
      form: {
        'formhash': formhash,
        'tid': '$tid',
        'pid': '$pid',
        'reason': reason,
        for (final entry in scores.entries) 'score${entry.key}': '${entry.value}',
        if (notify) 'sendreasonpm': 'on',
      },
    );
    _ensureOk(response);
    final msg = _rateMessage(response.body);
    if (msg.isNotEmpty && _looksLikeRateError(msg)) {
      throw SiteException(_rateErrorText(msg));
    }
    return msg.isEmpty ? '打赏成功' : msg;
  }

  /// 提取站点评分页 / 评分提交响应里的提示文案。
  ///
  /// `inajax` 返回的通常是 `errorhandle_rate('提示')` 这类脚本，
  /// 必须只取引号内的提示，避免把整段 JS 弹给用户。
  String _rateMessage(String body) {
    final cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true).firstMatch(body)?.group(1);
    final raw = cdata ?? body;
    final quoted = RegExp(
      r"(?:errorhandle_\w+|succeedhandle_\w+|showmessage|showDialog)\(\s*'([^']*)'",
    ).firstMatch(raw)?.group(1);
    if (quoted != null && _clean(quoted).isNotEmpty) return _clean(quoted);
    final page = _pageMessage(parser.parse(body)) ?? '';
    if (page.isNotEmpty) return page;
    final text = _clean(raw.replaceAll(RegExp(r'<[^>]+>'), ' '));
    if (_looksLikeRateError(text) && text.length < 80) return text;
    return '';
  }

  /// 评分页本身返回的错误提示（权限不足等）。
  String _rateNotice(String body) {
    final page = _pageMessage(parser.parse(body)) ?? '';
    return _looksLikeRateError(page) ? page : '';
  }

  String _rateErrorText(String message) {
    if (RegExp(r'24\s*小时评分数超过限制').hasMatch(message)) {
      return '24 小时内该积分项的评分额度已用完，请明天再试';
    }
    if (message.contains('不能给自己评分') || message.contains('不能评分自己')) {
      return '不能打赏自己的帖子';
    }
    if (message.contains('没有权限') || message.contains('无权')) {
      return '当前账号没有打赏权限';
    }
    return message;
  }

  bool _looksLikeRateError(String text) =>
      RegExp(r'(抱歉|错误|失败|不能|无权|权限|非法|禁止|请先登录|间隔|重复|超过限制)')
          .hasMatch(text);

  /// 踢帖：站点插件 `bin_post_report` 的确认页可能带有表单，按其字段原样提交。
  Future<String> kickThread({
    required int tid,
    required String token,
    required String formhash,
  }) async {
    final entry = await _http.get(
      'plugin.php',
      query: {
        'id': 'bin_post_report',
        'tid': '$tid',
        'm': token,
        'mobile': '2',
      },
      referer: _threadReferer(tid),
    );
    _ensureOk(entry);
    final doc = parser.parse(entry.body);
    final form = doc.querySelector('form');
    if (form == null) {
      final msg = _pageMessage(doc) ?? '';
      if (_looksLikeRateError(msg)) throw SiteException(msg);
      throw SiteException(msg.isEmpty ? '踢帖页面暂不可用，请在浏览器中操作' : msg);
    }

    final fields = <String, String>{};
    for (final input in form.querySelectorAll('input, textarea')) {
      final name = input.attributes['name'] ?? '';
      if (name.isEmpty) continue;
      final type = (input.attributes['type'] ?? 'text').toLowerCase();
      if (type == 'button' || type == 'image') continue;
      if (type == 'checkbox' || type == 'radio') {
        if (input.attributes.containsKey('checked')) {
          fields[name] = input.attributes['value'] ?? 'on';
        }
        continue;
      }
      fields[name] = input.localName == 'textarea'
          ? input.text
          : input.attributes['value'] ?? '';
    }
    for (final select in form.querySelectorAll('select')) {
      final name = select.attributes['name'] ?? '';
      if (name.isEmpty) continue;
      final selected = select.querySelector('option[selected]') ?? select.querySelector('option');
      fields[name] = selected?.attributes['value'] ?? '';
    }
    fields.putIfAbsent('formhash', () => formhash);

    final action = (form.attributes['action'] ?? '').trim().replaceFirst(RegExp(r'^\./'), '');
    final target = action.isEmpty
        ? AppConfig.uri('plugin.php', {'id': 'bin_post_report', 'tid': '$tid', 'm': token}).toString()
        : _absolute(action);
    final response = await _http.post(
      target,
      query: {'formhash': fields['formhash'] ?? formhash, 'mobile': '2'},
      referer: _threadReferer(tid),
      form: fields,
    );
    _ensureOk(response);
    final text = response.body.contains('<![CDATA[')
        ? _inajaxMessage(response.body)
        : (_pageMessage(parser.parse(response.body)) ?? '');
    if (_looksLikeRateError(text)) throw SiteException(text);
    return text.isEmpty ? '已提交踢帖' : text;
  }

  /// 版主管理：关闭 / 置顶回复 / 精华 / 警告 / 删除。
  /// 置顶回复必须传回复 pid；其它主题级操作仍提交 tid。
  Future<String> moderate({
    required int tid,
    required int fid,
    required String formhash,
    required String action,
    int? pid,
  }) async {
    if (action == 'stickreply') {
      return setStickReply(tid: tid, fid: fid, pid: pid ?? 0, formhash: formhash);
    }
    final response = await _http.post(
      'forum.php',
      query: {
        'mod': 'topicadmin',
        'action': action,
        'fid': '$fid',
        'tid': '$tid',
        'handlekey': 'topicadmin',
        'inajax': '1',
        'mobile': '2',
      },
      referer: _threadReferer(tid),
      form: {
        'formhash': formhash,
        'moderate[]': '$tid',
        if (action == 'digest') 'digest': '1',
      },
    );
    final msg = response.body.contains('<![CDATA[')
        ? _inajaxMessage(response.body)
        : (_pageMessage(parser.parse(response.body)) ?? '');
    if (msg.isNotEmpty && _looksLikeError(msg)) throw SiteException(msg);
    if (msg.isNotEmpty && (msg.contains('无权') || msg.contains('权限') ||
        msg.contains('没有权限') || msg.contains('不允许') || msg.contains('失败'))) {
      throw SiteException(msg);
    }
    final labels = {
      'close': '主题已关闭',
      'digest': '已设为精华',
      'warn': '已警告',
      'delete': '已删除',
    };
    return msg.isEmpty ? (labels[action] ?? '操作成功') : msg;
  }

  /// 置顶 / 取消置顶某条回复（Discuz 的 `topicadmin&action=stickreply`）。
  ///
  /// 这是主题作者自己也能用的操作（`forum_topicadmin.php` 里
  /// `$specialperm = action=='stickreply' && thread.authorid == uid`），
  /// 不需要版主权限。走的是确认框那张表单：`modsubmit=yes` + `topiclist[]`
  /// + `stickreply=1|0`，不是版主面板的 `moderate[]`。
  Future<String> setStickReply({
    required int fid,
    required int tid,
    required int pid,
    required String formhash,
    bool stick = true,
  }) async {
    if (pid <= 0) throw SiteException('缺少需要置顶的回复信息');
    final request = stickReplyRequest(
      fid: fid,
      tid: tid,
      pid: pid,
      formhash: formhash,
      stick: stick,
    );
    final response = await _http.post(
      'forum.php',
      query: request.$1,
      referer: _threadReferer(tid),
      form: request.$2,
    );
    final msg = response.body.contains('<![CDATA[')
        ? _inajaxMessage(response.body)
        : (_pageMessage(parser.parse(response.body)) ?? '');
    if (msg.isNotEmpty && _looksLikeError(msg)) throw SiteException(msg);
    if (msg.isNotEmpty &&
        (msg.contains('无权') || msg.contains('权限') || msg.contains('不允许') || msg.contains('失败'))) {
      throw SiteException(msg);
    }
    // 站点的通用回执就写「管理操作成功」，对用户没有信息量，换成具体动作。
    if (msg.isEmpty || msg == '管理操作成功' || msg == '操作成功') {
      return stick ? '置顶成功' : '已取消置顶';
    }
    return msg;
  }

  /// 置顶 / 取消置顶回复的表单。
  ///
  /// `forum_topicadmin.php` 走 `submitcheck('modsubmit')`：query 里必须有
  /// `modsubmit=yes`，body 里是确认框那张表单的 `topiclist[]` + `stickreply`，
  /// 不是版主面板的 `moderate[]`。
  @visibleForTesting
  static (Map<String, String>, Map<String, String>) stickReplyRequest({
    required int fid,
    required int tid,
    required int pid,
    required String formhash,
    required bool stick,
  }) =>
      (
        {
          'mod': 'topicadmin',
          'action': 'stickreply',
          'modsubmit': 'yes',
          'infloat': 'yes',
          'modclick': 'yes',
          'fid': '$fid',
          'tid': '$tid',
          'mobile': '2',
        },
        {
          'formhash': formhash,
          'fid': '$fid',
          'tid': '$tid',
          'handlekey': 'mods',
          'topiclist[]': '$pid',
          'stickreply': stick ? '1' : '0',
          'reason': '',
        },
      );

  /// 站内私信。
  Future<String> sendPm({
    required int uid,
    required String formhash,
    required String message,
  }) async {
    final response = await _http.post(
      'home.php',
      query: {
        'mod': 'spacecp',
        'ac': 'pm',
        'op': 'send',
        'touid': '$uid',
        'pmsubmit': 'yes',
        'inajax': '1',
        'mobile': '2',
      },
      form: {
        'formhash': formhash,
        'touid': '$uid',
        'message': message,
      },
    );
    final failure = sendPmFailure(response.body);
    if (failure != null) throw SiteException(failure);
    return '私信已发送';
  }

  /// 私信到底发出去没有。
  ///
  /// `inajax=1` 的响应是一段 `succeedhandle_pm('…')` / `errorhandle_pm('…')`
  /// 脚本，页面上那些提示容器一个都匹配不上。早先拿 `_pageMessage` 去读，
  /// 读到的永远是 null，于是无论发没发出去都提示「已发送」。
  @visibleForTesting
  static String? sendPmFailure(String body) {
    final failed = body.contains('errorhandle') ||
        RegExp(r'(发送失败|抱歉|不能|无权|禁止|超出|太频繁|非法)').hasMatch(_inajaxText(body));
    if (!failed) return null;
    final message = _inajaxText(body);
    return message.isEmpty ? '私信发送失败，请稍后重试' : message;
  }

  static String _inajaxText(String body) {
    final cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true).firstMatch(body)?.group(1) ?? body;
    final call = RegExp(r'''(?:succeedhandle|errorhandle)_\w+\s*\((.{0,300}?)\)\s*;''', dotAll: true)
        .firstMatch(cdata);
    if (call != null) {
      final quoted = RegExp(r'''['"]([^'"]*)['"]''').allMatches(call.group(1)!).map((m) => m.group(1) ?? '');
      for (final text in quoted) {
        if (text.trim().isNotEmpty) return _clean(text);
      }
    }
    return _clean(cdata.replaceAll(RegExp(r'<[^>]+>'), ' '));
  }

  /// 他人主页资料。`hash` 为关注操作所需的 formhash。
  Future<(UserProfile, String, bool)> fetchUserProfile(int uid) async {
    final result = await _http.get(
      'home.php',
      query: {'mod': 'space', 'uid': '$uid', 'do': 'profile', 'mobile': '2'},
    );
    _ensureOk(result);
    final doc = parser.parse(result.body);
    final isFollowing = _isFollowingOnProfile(doc, result.body, uid);
    return (
      _parseSpaceProfile(doc, result.body, uid: uid),
      _findFormhash(result.body),
      isFollowing,
    );
  }

  Future<List<ThreadSummary>> fetchUserThreads(int uid, {int page = 1}) => fetchPersonalList(
        'home.php',
        query: {
          'mod': 'space',
          'uid': '$uid',
          'do': 'thread',
          'view': 'me',
          'mobile': '2',
          'page': '$page',
        },
      );

  /// 回复列表。Discuz 没有 `do=reply`，正确入口是
  /// `do=thread&view=me&type=reply`，且回复行只有 findpost 链接、没有 thread- 链接。
  Future<List<ThreadSummary>> fetchUserReplies(int uid, {int page = 1}) async {
    final query = <String, String>{
      'mod': 'space',
      'do': 'thread',
      'view': 'me',
      'type': 'reply',
      'from': 'space',
      'page': '$page',
      if (uid > 0) 'uid': '$uid',
    };
    // 桌面模板会额外输出每条回复的正文摘要，结构也更稳定，优先使用。
    final desktop = await _getDesktopPage('home.php', query);
    if (desktop.ok) {
      final parsed = _parseSpaceReplies(desktop.body);
      if (parsed.isNotEmpty) return parsed;
    }
    final mobile = await _http.get('home.php', query: {...query, 'mobile': '2'});
    _ensureOk(mobile);
    return _parseSpaceReplies(mobile.body);
  }

  /// 我的回复（不带 uid，服务端自动取当前登录用户）。
  Future<List<ThreadSummary>> fetchMyReplies({int page = 1}) => fetchUserReplies(0, page: page);

  /// 从他人主页的关注操作入口识别当前登录账号是否已关注该用户。
  /// Discuz/Comiis 会按状态输出「取消关注」入口或关注状态按钮；未登录时保持 false。
  bool _isFollowingOnProfile(Document doc, String html, int uid) {
    if (!_http.hasLoginCookie || uid <= 0) return false;
    for (final link in doc.querySelectorAll('a[href], button, input[type=button], input[type=submit]')) {
      final href = (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
      final label = _clean(link.attributes['value'] ?? link.text);
      final isFollowAction = href.contains('ac=follow') &&
          (href.contains('op=del') || href.contains('op=delete')) &&
          (href.contains('fuid=$uid') || href.contains('fuid%3D$uid'));
      if (isFollowAction || label == '已关注' || label == '取消关注' || label == '取消收听') {
        return true;
      }
    }
    // 兼容模板将按钮写在脚本/属性中的情况，但只匹配目标 UID 的取消关注地址。
    return RegExp(r"""(?:ac=follow[^"'<>]{0,160}op=del[^"'<>]{0,160}fuid=$uid|fuid=$uid[^"'<>]{0,160}ac=follow[^"'<>]{0,160}op=del)""", caseSensitive: false).hasMatch(html);
  }

  /// 关注 / 取消关注用户。
  Future<bool> followUser({required int uid, required bool follow, required String hash}) async {
    if (hash.isEmpty) throw SiteException('操作凭证已失效，请重新进入主页');
    final result = await _http.get(
      'home.php',
      query: {
        'mod': 'spacecp',
        'ac': 'follow',
        'op': follow ? 'add' : 'del',
        'hash': hash,
        'fuid': '$uid',
        'from': 'space',
        'mobile': '2',
      },
      referer: AppConfig.uri('home.php', {'mod': 'space', 'uid': '$uid'}).toString(),
    );
    _ensureOk(result);
    final msg = _pageMessage(parser.parse(result.body));
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    return follow;
  }

  /// 我的好友列表。
  Future<List<FriendItem>> fetchFriends({int page = 1}) async {
    final result = await _http.get(
      'home.php',
      query: {
        'mod': 'space',
        'do': 'friend',
        'view': 'me',
        'mobile': '2',
        'page': '$page',
      },
    );
    _ensureOk(result);
    final doc = parser.parse(result.body);
    final items = <FriendItem>[];
    final seen = <int>{};
    // 移动端 comiis 模板：div.comiis_userlist01 > li；桌面模板回落 ul.buddy / #friend_ul。
    for (final selector in ['.comiis_userlist01 li', '#friend_ul li', 'ul.buddy li']) {
      for (final element in doc.querySelectorAll(selector)) {
        // 无好友时页面会推荐好友 / 在线成员，带「加好友」按钮的不是已有好友。
        if (element.querySelector('a[href*="ac=friend&op=add"]') != null) continue;
        final nameLink = element.querySelector('p.tit a[href*="mod=space&uid="]') ??
            element.querySelector('p.tit a') ??
            element.querySelector('h4 a[href*="mod=space&uid="]') ??
            element.querySelector('h4 a') ??
            element.querySelector('.comiis_friend_name, .name');
        final name = _clean(nameLink?.text ?? '');
        if (name.isEmpty) continue;
        var uid = 0;
        for (final link in element.querySelectorAll('a[href]')) {
          uid = _uidFromHref(link.attributes['href'] ?? '');
          if (uid > 0) break;
        }
        if (uid <= 0 || !seen.add(uid)) continue;
        final avatarEl = element.querySelector('a.list01_limg img') ??
            element.querySelector('dd.avt img') ??
            element.querySelector('img');
        items.add(FriendItem(
          uid: uid,
          username: name,
          avatar: avatarEl == null ? '' : _pickImage(avatarEl),
          note: _clean(
            element.querySelector('p.txt, .note, .comiis_friend_note')?.text ?? '',
          ),
        ));
        if (items.length >= 80) break;
      }
      if (items.isNotEmpty) break;
    }
    return items;
  }

  /// 我的关注列表（Discuz 用户关注页）。使用当前登录账号的 UID，不固定用户编号。
  Future<List<FriendItem>> fetchFollowing(int uid, {int page = 1}) =>
      _fetchFollowList('following', uid, page: page);

  /// 我的粉丝列表。与关注列表共用一套模板（`#follow_ul` / `.comiis_userlist01`），
  /// 只是 `do=follower`，因此复用同一套行解析。
  Future<List<FriendItem>> fetchFollowers(int uid, {int page = 1}) =>
      _fetchFollowList('follower', uid, page: page);

  Future<List<FriendItem>> _fetchFollowList(String action, int uid, {int page = 1}) async {
    if (uid <= 0) throw SiteException('无法识别当前用户，请刷新个人资料后重试');
    final label = action == 'follower' ? '粉丝' : '关注';
    final query = <String, String>{
      'mod': 'follow',
      'do': action,
      'uid': '$uid',
      'page': '$page',
    };
    final mobile = await _http.get('home.php', query: {...query, 'mobile': '2'});
    _ensureOk(mobile);
    var items = _parseFollowRows(mobile.body);
    if (items.isNotEmpty) return items;

    // 站点桌面模板的关注/粉丝列表结构更稳定，移动模板没有解析到时再回退。
    final desktop = await _getDesktopPage('home.php', query);
    _ensureOk(desktop);
    items = _parseFollowRows(desktop.body);
    if (items.isEmpty) {
      final message = _pageMessage(parser.parse(desktop.body)) ?? _clean(parser.parse(desktop.body).body?.text ?? '');
      if (message.contains('登录') || message.contains('权限')) {
        throw SiteException(message.length > 120 ? '无法读取$label列表，请确认登录状态' : message);
      }
    }
    return items;
  }

  /// 关注 / 粉丝列表的行解析。
  ///
  /// 每一行除了头像、昵称，还有「6 关注」「4 粉丝」这类计数链接，它们同样带 uid。
  /// 如果直接取行内第一个带 uid 的链接，昵称就会变成「6 关注」（网页端显示的是昵称），
  /// 所以这里按链接语义筛选：只认个人空间链接，排除 do=following / do=follower 计数链接，
  /// 以及「取消关注」「备注」「星标」等操作链接。
  List<FriendItem> _parseFollowRows(String html) {
    final doc = parser.parse(html);
    _followingFormhash = _findFormhash(html);
    final items = <FriendItem>[];
    final seen = <int>{};
    const selectors = <String>[
      // Discuz 触屏版：div.xld > dl.b_b（关注 / 粉丝各一行）。
      '.xld dl',
      '.xlda dl',
      'dl.b_b',
      '#follow_ul li',
      '.comiis_userlist01 li',
      '.comiis_followlist li',
      '.comiis_follow_list li',
      '.followlist li',
      '.follow_list li',
      '.space_list li',
      '.comiis_uitem',
      '.buddy li',
      '.mtli li',
      'ul[id*="follow"] li',
    ];
    for (final selector in selectors) {
      for (final element in doc.querySelectorAll(selector)) {
        Element? profileLink;
        var uid = 0;
        for (final link in element.querySelectorAll('a[href]')) {
          final href = (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
          final text = _clean(link.text);
          final candidate = _uidFromHref(href);
          if (candidate <= 0 || _isFollowCountLink(href) || _isFollowActionLabel(text)) continue;
          // mod=spacecp 是「关注 / 备注 / 星标」等操作入口，不是个人主页。
          if (href.contains('mod=spacecp') || href.contains('ac=follow')) continue;
          final isProfile = href.contains('mod=space') ||
              href.contains('space-uid-') ||
              href.contains('do=profile') ||
              href.contains('uid=');
          if (!isProfile) continue;
          profileLink = link;
          uid = candidate;
          break;
        }

        // 有些模板把昵称放在标题节点里，链接不直接带 uid；此时只接受
        // 头像/昵称周围明确的个人空间链接，不从「取消关注」操作中猜 uid。
        if (profileLink == null) {
          final candidateLink = element.querySelector(
            'h2 a[href], h3 a[href], h4 a[href], .username a[href], .name a[href], .avt a[href]',
          );
          final href = candidateLink?.attributes['href'] ?? '';
          final candidateName = _clean(candidateLink?.text ?? '');
          final candidateUid = _uidFromHref(href);
          if (candidateLink != null &&
              candidateName.isNotEmpty &&
              !_isFollowActionLabel(candidateName) &&
              !_isFollowCountLink(href) &&
              candidateUid > 0) {
            profileLink = candidateLink;
            uid = candidateUid;
          }
        }
        if (profileLink == null || uid <= 0 || !seen.add(uid)) continue;

        final name = _clean(profileLink.text);
        if (name.isEmpty || _isFollowActionLabel(name)) continue;

        final avatar = element.querySelector('img');
        // 备注只取昵称旁边的节点，别把下面「粉丝: 4 关注: 6」当备注。
        final noteNode = element.querySelector('dt span.xg1, dt span.xs1, .note, .desc');
        final noteText = _clean(noteNode?.text ?? '');
        final note = _isFollowCountLabel(noteText) ||
                RegExp(r'(?:粉丝|关注)\s*[:：]').hasMatch(noteText)
            ? ''
            : noteText;
        final starLink = element.querySelector('a[id^="a_specialfollow_"][href*="special="]') ??
            element.querySelector('a[href*="special="][href*="fuid="]');
        final starHref = starLink?.attributes['href'] ?? '';
        final starLabel = _clean(starLink?.text ?? '');
        final isStarred = RegExp(r'[?&]special=2(?:&|$)').hasMatch(starHref) && starLabel.contains('取消');
        final rowText = _clean(element.text);
        final counts = _followCounts(rowText);
        items.add(FriendItem(
          uid: uid,
          username: name,
          avatar: avatar == null ? '' : _pickImage(avatar),
          note: note,
          followers: counts.$2,
          following: counts.$1,
          isStarred: isStarred,
        ));
      }
      if (items.isNotEmpty) break;
    }
    return items;
  }

  /// 取出「关注 / 粉丝」数量，兼容两种排版：
  /// - 「6 关注」「1,024 粉丝」（数字在前）
  /// - 「粉丝: 4 人」「关注: 6 人」（Discuz 触屏版，标签在前）
  (int, int) _followCounts(String text) {
    final labelFirst = RegExp(r'(?:粉丝|关注)\s*[:：]').hasMatch(text);
    int pick(String unit) {
      final pattern = labelFirst
          ? '$unit\\s*[:：]?\\s*([0-9][0-9,]*)'
          : '([0-9][0-9,]*)\\s*$unit';
      final match = RegExp(pattern).firstMatch(text);
      return int.tryParse(match?.group(1)?.replaceAll(',', '') ?? '') ?? 0;
    }

    return (pick('关注'), pick('粉丝'));
  }

  /// 关注 / 粉丝页里的计数链接（`do=following`、`do=follower`），不能当昵称。
  bool _isFollowCountLink(String href) =>
      href.contains('do=following') || href.contains('do=follower');

  bool _isFollowCountLabel(String text) =>
      RegExp(r'^\d[\d,]*\s*(?:关注|粉丝|好友|主题|帖子)$').hasMatch(text) ||
      text == '关注' ||
      text == '粉丝';

  bool _isFollowActionLabel(String text) {
    if (text.isEmpty) return true;
    if (_isFollowCountLabel(text)) return true;
    const labels = <String>{
      '取消', '取消关注', '关注', '已关注', '回关', '备注', '星标', '取消星标',
      '访问主页', '删除', '查看', '私信', '发消息', '加好友', '打招呼',
    };
    return labels.contains(text) ||
        text.startsWith('取消') ||
        text.startsWith('备注') ||
        text.startsWith('星标');
  }


  /// 取消关注：Discuz X 标准动作。
  Future<void> cancelFollowing(int uid) async {
    if (uid <= 0) throw SiteException('用户编号无效');
    final result = await _http.get('home.php', query: {
      'mod': 'spacecp', 'ac': 'follow', 'op': 'del', 'fuid': '$uid', 'inajax': '1', 'mobile': '2',
    }, referer: AppConfig.uri('home.php?mod=follow&do=following').toString());
    _ensureOk(result);
    final message = _inajaxMessage(result.body);
    if (_looksLikeError(message) || message.contains('登录')) {
      throw SiteException(message.isEmpty ? '取消关注失败，请稍后重试' : message);
    }
  }

  /// 设置特别关注。Discuz 模板约定 special=1 添加、special=2 取消。
  Future<void> setFollowingStar(int uid, {required bool starred}) async {
    if (uid <= 0) throw SiteException('用户编号无效');
    if (_followingFormhash.isEmpty) throw SiteException('操作凭证已失效，请刷新关注列表后重试');
    final result = await _http.get('home.php', query: {
      'mod': 'spacecp', 'ac': 'follow', 'op': 'add', 'hash': _followingFormhash,
      'special': starred ? '1' : '2', 'fuid': '$uid', 'inajax': '1', 'mobile': '2',
    }, referer: AppConfig.uri('home.php?mod=follow&do=following').toString());
    _ensureOk(result);
    final message = _inajaxMessage(result.body);
    if (_looksLikeError(message) || message.contains('登录')) {
      throw SiteException(message.isEmpty ? '星标操作失败，请稍后重试' : message);
    }
  }

  /// 读取站点备注表单后提交，沿用其 formhash 和字段名。
  Future<String> setFollowingNote(int uid, String note) async {
    if (uid <= 0) throw SiteException('用户编号无效');
    final query = {'mod': 'spacecp', 'ac': 'follow', 'op': 'bkname', 'fuid': '$uid', 'handlekey': 'followbkname_$uid'};
    final page = await _http.get('home.php', query: query,
      referer: AppConfig.uri('home.php?mod=follow&do=following').toString());
    _ensureOk(page);
    final doc = parser.parse(page.body);
    final form = doc.querySelector('form[action*="op=bkname"]');
    final formhash = form?.querySelector('input[name="formhash"]')?.attributes['value'] ?? _findFormhash(page.body);
    if (form == null || formhash.isEmpty) {
      throw SiteException(_pageMessage(doc) ?? '无法读取备注表单，请确认登录状态后重试');
    }
    final response = await _http.post('home.php', query: query,
      referer: AppConfig.uri('home.php?mod=spacecp&ac=follow&op=bkname&fuid=$uid').toString(),
      form: {
        'formhash': formhash, 'referer': AppConfig.uri('home.php?mod=follow&do=following').toString(),
        'editbkname': 'true', 'bkname': note.trim(), 'handlekey': 'followbkname_$uid',
      });
    _ensureOk(response);
    final resultDoc = parser.parse(response.body);
    final message = _pageMessage(resultDoc) ?? _inajaxMessage(response.body);
    if (_looksLikeError(message) || message.contains('登录')) {
      throw SiteException(message.isEmpty ? '保存备注失败，请稍后重试' : message);
    }
    return note.trim();
  }

  /// 以桌面模板读取页面：结构稳定，读取后立即清掉服务端写入的 mobile=no Cookie，
  /// 避免后续请求也跟着切到桌面模板。
  Future<HttpResult> _getDesktopPage(String path, Map<String, String> query) async {
    final result = await _http.get(
      path,
      query: {...query, 'mobile': 'no'},
      userAgent: _desktopUserAgent,
    );
    _http.removeCookie('mobile');
    return result;
  }

  /// 私信会话列表。桌面模板结构固定，避免移动端模板差异导致昵称/头像解析失败。
  Future<List<PmConversation>> fetchPmConversations({int page = 1}) async {
    final result = await _getDesktopPage('home.php', {
      'mod': 'space',
      'do': 'pm',
      'filter': 'privatepm',
      'page': '$page',
    });
    _ensureOk(result);
    return _parsePmConversations(result.body);
  }

  /// 解析私信会话列表 HTML，仅供测试与离线比对。
  List<PmConversation> parsePmListHtml(String html) => _parsePmConversations(html);

  List<PmConversation> _parsePmConversations(String html) {
    final doc = parser.parse(html);
    final items = <PmConversation>[];
    final seen = <int>{};
    for (final node in doc.querySelectorAll('dl[id^="pmlist_"]')) {
      var uid = _pmPeerUid(node);
      if (uid <= 0) {
        // 少数模板的会话链接不带 touid，改用行内指向个人空间的链接。
        for (final link in node.querySelectorAll('a[href]')) {
          final candidate = _uidFromHref(link.attributes['href'] ?? '');
          if (candidate > 0) {
            uid = candidate;
            break;
          }
        }
      }
      if (uid <= 0 || !seen.add(uid)) continue;
      final name = _pmPeerName(node, uid);
      final avatarEl = node.querySelector('dd.avt img');
      final preview = _pmNodeText(node);
      if (name.isEmpty && preview.isEmpty) continue;
      items.add(PmConversation(
        uid: uid,
        name: name,
        avatar: avatarEl == null ? '' : _pickImage(avatarEl),
        preview: preview,
        time: _clean(node.querySelector('dd.ptm span.xg1')?.text ?? ''),
        // newpm_avt 在每条会话里都会输出，靠 CSS 控制显示，不能用它判断未读。
        unread: node.classes.contains('newpm'),
      ));
      if (items.length >= 40) break;
    }
    return items;
  }

  /// 与某个用户的私信记录，返回（消息、formhash、对方昵称）。
  Future<(List<PmMessage>, String, String)> fetchPmMessages(int uid, {int myUid = 0}) async {
    final result = await _getDesktopPage('home.php', {
      'mod': 'space',
      'do': 'pm',
      'subop': 'view',
      'touid': '$uid',
    });
    _ensureOk(result);
    return _parsePmMessages(result.body, uid: uid, myUid: myUid);
  }

  /// 解析私信会话 HTML，仅供测试与离线比对。
  (List<PmMessage>, String, String) parsePmMessagesHtml(
    String html, {
    required int peerUid,
    int myUid = 0,
  }) =>
      _parsePmMessages(html, uid: peerUid, myUid: myUid);

  (List<PmMessage>, String, String) _parsePmMessages(
    String html, {
    required int uid,
    int myUid = 0,
  }) {
    final doc = parser.parse(html);
    final messages = <PmMessage>[];
    var peer = '';
    for (final node in doc.querySelectorAll('dl[id^="pmlist_"]')) {
      final text = _pmNodeText(node);
      if (text.isEmpty) continue;
      final authorLink = _pmAuthorLink(node);
      final authorUid = _pmAuthorUid(node);
      // 作者 uid 才是判断归属的依据：对方的消息带头像/昵称链接，
      // 自己的消息在默认模板里只有「您」标记。只看链接文字会把昵称
      // 不是链接的模板全判成「自己」，于是整屏消息都挤在右侧。
      final mine = authorUid > 0
          ? (myUid > 0 ? authorUid == myUid : uid > 0 && authorUid != uid)
          : _pmHasSelfMarker(node);
      final author = _clean(authorLink?.text ?? '');
      if (!mine && author.isNotEmpty && peer.isEmpty) peer = author;
      messages.add(PmMessage(
        text: text,
        author: author,
        uid: authorUid,
        time: _clean(node.querySelector('dd.ptm span.xg1, dd.ptm .xg1')?.text ?? ''),
        mine: mine,
      ));
    }
    if (peer.isEmpty) {
      peer = _clean(
        RegExp(r'与\s*(\S+)\s*的短消息').firstMatch(doc.querySelector('title')?.text ?? '')?.group(1) ?? '',
      );
    }
    return (messages, _findFormhash(html), peer);
  }

  /// 从链接里取用户 uid：兼容 home.php?...&uid=1、&fuid=1 与 space-uid-1.html 两种写法。
  int _uidFromHref(String href) {
    final match = RegExp(r'(?:[?&](?:amp;)?(?:uid|fuid)=|space-uid-)(\d+)').firstMatch(href);
    return _firstInt(match?.group(1)) ?? 0;
  }

  /// 私信节点正文：取第一个 <br> 之后的内容，跳过时间与操作菜单。
  String _pmNodeText(Element node) {
    final body = node.querySelector('dd.ptm') ?? node;
    final buffer = StringBuffer();
    var afterBreak = false;
    for (final child in body.nodes) {
      if (child is Element) {
        if (child.localName == 'br') {
          afterBreak = true;
          continue;
        }
        if (!afterBreak) continue;
        final classes = child.classes;
        if (classes.contains('xg1') || classes.contains('p_pop') || child.localName == 'script') {
          continue;
        }
        // pm_o 在默认模板里是「共 N 条 · 菜单 | 回复」的操作区，
        // p_pop 里还藏着一个 hover 才弹出的下拉（删除 / 忽略）。
        // 这些东西靠 CSS 摆到右侧、悬停才出现，直接取文本会一起塞进摘要。
        // 个别主题拿 pm_o 装正文，所以只在带菜单按钮时才认定是操作区。
        if (classes.contains('pm_o')) {
          if (child.querySelector('.p_pop') != null || child.querySelector('a.o') != null) {
            continue;
          }
          if (_clean(child.text).length <= 6) continue;
        }
        if (child.id.contains('menu')) continue;
        buffer.write(_pmVisibleText(child));
      } else if (afterBreak) {
        buffer.write(child.text);
      }
    }
    return _clean(buffer.toString());
  }

  /// 取元素里的「看得见」的文本。
  ///
  /// Discuz 把「删除 / 忽略」放在 `display:none` 的下拉层里、把「菜单」做成
  /// 一个纯 JS 按钮，网页端靠 CSS 和鼠标悬停控制出现时机。App 只读 DOM，
  /// 不认这层「视觉上不存在」，就会把整排操作词当成消息正文的一部分。
  String _pmVisibleText(Element el) {
    final buffer = StringBuffer();
    void walk(Node node) {
      if (node is Text) {
        buffer.write(node.text);
        return;
      }
      if (node is! Element) return;
      final style = (node.attributes['style'] ?? '').replaceAll(' ', '').toLowerCase();
      if (style.contains('display:none')) return;
      if (node.classes.contains('p_pop')) return;
      if (node.localName == 'script' || node.localName == 'style') return;
      // 只有「菜单」两个字的悬浮按钮，点开才是下拉层。
      if (node.localName == 'a' && node.classes.contains('o')) return;
      for (final child in node.nodes) {
        walk(child);
      }
    }

    walk(el);
    return buffer.toString();
  }

  /// 会话对应的对方 uid：优先取会话链接里的 touid。
  int _pmPeerUid(Element node) {
    for (final link in node.querySelectorAll('a[href]')) {
      final uid = _touidFromHref(link.attributes['href'] ?? '');
      if (uid > 0) return uid;
    }
    return 0;
  }

  /// 取 `touid=` 参数，用于定位私信会话的对方。
  int _touidFromHref(String href) {
    final match = RegExp(r'[?&](?:amp;)?touid=(\d+)').firstMatch(href);
    return _firstInt(match?.group(1)) ?? 0;
  }

  /// 私信正文里的作者链接：跳过会话跳转链接，兼容两种个人空间地址。
  Element? _pmAuthorLink(Element node) {
    for (final link in node.querySelectorAll('dd.ptm a[href], a[href]')) {
      final href = (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
      if (href.contains('do=pm') || href.contains('ac=pm')) continue;
      if (_uidFromHref(href) <= 0) continue;
      if (_clean(link.text).isEmpty) continue;
      return link;
    }
    return null;
  }

  /// 消息作者 uid：头像链接、昵称链接都指向作者本人，优先取头像那一层，
  /// 这样即使模板把昵称写成纯文本，也能判断是「我」还是「对方」。
  int _pmAuthorUid(Element node) {
    for (final selector in <String>['dd.avt a[href]', 'dt a[href]', 'dd.ptm a[href]']) {
      for (final link in node.querySelectorAll(selector)) {
        final href = (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
        if (href.contains('do=pm') || href.contains('ac=pm')) continue;
        final uid = _uidFromHref(href);
        if (uid > 0) return uid;
      }
    }
    return 0;
  }

  /// 模板给「自己」的消息只输出「您 / 我」，没有任何作者链接。
  bool _pmHasSelfMarker(Element node) {
    for (final element in node.querySelectorAll('span, strong, em, a, cite')) {
      final text = _clean(element.text);
      if (text == '您' || text == '我' || text == '自己') return true;
    }
    return false;
  }

  /// 私信会话里对方的昵称。
  ///
  /// 站点的私信列表同时存在 `home.php?mod=space&uid=1` 与
  /// `space-uid-1.html` 两种个人空间写法，模板也可能把昵称放在 `dt` / `cite`
  /// 里而不是链接文字中，所以这里按 uid 匹配后逐级回退，避免整列显示成「UID 数字」。
  String _pmPeerName(Element node, int uid) {
    String? firstCandidate;
    for (final link in node.querySelectorAll('a[href]')) {
      final text = _clean(link.text);
      if (!_usablePmName(text)) continue;
      final href = (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
      if (href.contains('do=pm') || href.contains('ac=pm')) continue;
      final linkUid = _uidFromHref(href);
      if (linkUid <= 0) continue;
      if (linkUid == uid) return text;
      firstCandidate ??= text;
    }
    for (final selector in <String>['dt', 'cite', 'strong.name', '.name', 'h3', '.xw1', '.xi2']) {
      for (final element in node.querySelectorAll(selector)) {
        final text = _clean(element.text);
        if (_usablePmName(text)) return text;
      }
    }
    if (firstCandidate != null) return firstCandidate;
    // 有些主题只给头像，昵称藏在 img[alt] 里。
    for (final image in node.querySelectorAll('img[alt]')) {
      final alt = _clean(image.attributes['alt'] ?? '');
      if (_usablePmName(alt) && alt != 'systempm' && !alt.contains('avatar')) return alt;
    }

    // 兜底：昵称既不是链接也不在常见容器里时，取行内第一个短文本，
    // 但要排除时间、正文预览和「您」这类标记，避免把预览当昵称。
    final preview = _pmNodeText(node);
    for (final element in node.querySelectorAll('span, a, strong, em, h3, h4, cite, p')) {
      if (element.children.isNotEmpty) continue;
      final text = _clean(element.text);
      if (!_usablePmName(text)) continue;
      if (text == preview || (preview.length > 1 && preview.startsWith(text))) continue;
      return text;
    }
    return '';
  }

  bool _usablePmName(String text) =>
      text.isNotEmpty &&
      text.length <= 24 &&
      !_looksLikeTime(text) &&
      text != '您' &&
      text != '我' &&
      !RegExp(r'^UID\s*\d+$').hasMatch(text) &&
      !RegExp(r'^\d+$').hasMatch(text);

  /// 形如「2026-7-25 18:33」「昨天 12:00」的时间串，不能当作昵称。
  bool _looksLikeTime(String text) =>
      RegExp(r'^\d{4}-\d{1,2}-\d{1,2}').hasMatch(text) ||
      RegExp(r'^\d{1,2}:\d{2}$').hasMatch(text) ||
      RegExp(r'^(昨天|今天|前天)').hasMatch(text);

  /// 消息提醒（我的帖子 / 坛友互动 / 系统提醒 / 应用提醒）。
  ///
  /// 手机模板与桌面模板结构差异很大，这里不绑定单一选择器：先按「提醒行」收集，
  /// 再把行内每个链接归类成主题 / 用户 / 私信三种目标。
  /// 这样「查看」这类只有文字、没有目标的链接不会单独变成一条提醒，
  /// 每条提醒在解析阶段就确定了点击后要打开的页面。
  Future<List<NoticeItem>> fetchNotices({String view = '', int page = 1}) async {
    final query = <String, String>{
      'mod': 'space',
      'do': 'notice',
      if (view.isNotEmpty) 'view': view,
      'page': '$page',
    };
    final mobile = await _http.get('home.php', query: {...query, 'mobile': '2'});
    _ensureOk(mobile);
    var items = _parseNoticeRows(mobile.body, view: view);
    if (items.isNotEmpty) return items;

    // 移动模板在部分主题下不渲染提醒列表，回落到结构稳定的桌面模板。
    final desktop = await _getDesktopPage('home.php', query);
    _ensureOk(desktop);
    items = _parseNoticeRows(desktop.body, view: view);
    if (items.isEmpty) {
      final message = _pageMessage(parser.parse(desktop.body)) ?? '';
      if (message.contains('登录') || message.contains('权限')) {
        throw SiteException(message.length > 120 ? '无法读取消息提醒，请确认登录状态' : message);
      }
    }
    return items;
  }

  /// 解析提醒页面 HTML。界面走 [fetchNotices]，这里公开只是为了便于单元测试
  /// 和抓取到的页面离线比对。
  List<NoticeItem> parseNoticeHtml(String html, {String view = ''}) =>
      _parseNoticeRows(html, view: view);

  /// 解析关注 / 粉丝列表 HTML，同样仅供测试与离线比对。
  List<FriendItem> parseFollowHtml(String html) => _parseFollowRows(html);

  /// 提醒里属于「操作 / 说明」而不是提醒正文的链接文字。
  static const Set<String> _noticeNoiseLabels = <String>{
    '查看', '查看详情', '详情', '查看更多', '更多', '查看全部', '全部',
    '标记已读', '忽略', '删除', '全部已读', '设置为已读',
  };

  /// 提醒页顶部 / 底部的频道导航文字，容易被误判成一条提醒。
  static const Set<String> _noticeNavLabels = <String>{
    '消息', '我的消息', '私信', '短消息', '提醒', '我的提醒', '全部提醒',
    '我的帖子', '坛友互动', '系统提醒', '应用提醒', '设为已读',
  };

  List<NoticeItem> _parseNoticeRows(String html, {required String view}) {
    final doc = parser.parse(html);
    final items = <NoticeItem>[];
    final seen = <String>{};

    void collect(Iterable<Element> rows) {
      for (final row in rows) {
        final item = _buildNotice(row, view: view);
        if (item == null) continue;
        final key = '${item.target.name}|${item.tid}|${item.uid}|${item.title}|${item.time}';
        if (!seen.add(key)) continue;
        items.add(item);
        if (items.length >= 60) return;
      }
    }

    const rowSelectors = <String>[
      // Discuz 触屏版：div#notice_ul > div.notice-list-item > div.notice-list-body。
      '.notice-list-item',
      '.nts > dl',
      '.nts dl',
      '.nts > li',
      'dl[id^="notice_"]',
      'li[id^="notice_"]',
      '.comiis_notice_item',
      '.comiis_noticeli',
      '.comiis_notice li',
      '.comiis_notice dl',
      '.comiis_notice_list li',
      '.notice li',
      '.notice_list li',
      '.space_notice li',
      '.noticeitem',
      '.comiis_uitem',
    ];
    final rows = <Element>[];
    for (final selector in rowSelectors) {
      rows.addAll(doc.querySelectorAll(selector));
    }
    collect(rows);

    // 兜底：模板把提醒铺在普通 li / dl 里时，用行内是否有可跳转链接反推。
    if (items.isEmpty) {
      final candidates = <Element>[];
      for (final link in doc.querySelectorAll('a[href]')) {
        final href = (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
        if (_tidFromHref(href) <= 0 && !_isPmLink(href) && _uidFromHref(href) <= 0) continue;
        final row = _noticeRowOf(link);
        if (row == null || _inPageChrome(row)) continue;
        if (!candidates.contains(row)) candidates.add(row);
      }
      collect(candidates);
    }
    return items;
  }

  /// 站点头部导航、页脚里的链接不是提醒，兜底解析时必须排除。
  bool _inPageChrome(Element node) {
    Element? current = node;
    for (var depth = 0; depth < 8 && current != null; depth++) {
      final tag = current.localName?.toLowerCase() ?? '';
      if (tag == 'header' || tag == 'footer' || tag == 'nav') return true;
      final id = current.id;
      if (id == 'hd' || id == 'ft' || id == 'nv' || id == 'scrolltop' || id == 'append_parent') return true;
      final classes = current.classes;
      if (classes.any((name) =>
          name.contains('footer') ||
          name.contains('comiis_nv') ||
          name.contains('comiis_nav') ||
          name.contains('comiis_tab') ||
          name == 'dhnv' ||
          name.contains('tabnav'))) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  /// 从链接向上找提醒行，最多走到 li / dl / tr 或带 notice 类名且确实含正文的 div。
  Element? _noticeRowOf(Element link) {
    Element? node = link.parent;
    for (var depth = 0; depth < 6 && node != null; depth++) {
      final tag = node.localName?.toLowerCase() ?? '';
      if (tag == 'li' || tag == 'dl' || tag == 'tr') return node;
      // .notice-list-avatar 这类容器同属「notice」命名空间，但只有图片没有正文。
      if (tag == 'div' &&
          node.classes.any((name) => name.contains('notice')) &&
          node.text.trim().length >= 6) {
        return node;
      }
      node = node.parent;
    }
    return null;
  }

  NoticeItem? _buildNotice(Element row, {required String view}) {
    final body = row.querySelector(
          '.notice-list-body, .ntc_body, .comiis_notice_content, .comiis_notice_text, '
          '.comiis_notice_desc, dd',
        ) ??
        row;
    final raw = _clean(body.text);
    if (raw.isEmpty || raw.length > 1200) return null;

    final time = _clean(row
            .querySelector('time, .notice-list-time, .ntc_time, .comiis_notice_time, '
                '.time, .dateline, .xg1, .grey')
            ?.text ??
        '');

    var tid = 0;
    var uid = 0;
    var pmUid = 0;
    var isPm = false;
    var threadUrl = '';
    var userUrl = '';
    var pmUrl = '';
    for (final link in body.querySelectorAll('a[href]')) {
      final href = (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
      if (href.isEmpty || href.startsWith('javascript:') || href == '#') continue;
      final label = _clean(link.text);
      final linkTid = _tidFromHref(href);
      if (linkTid > 0) {
        if (tid == 0) {
          tid = linkTid;
          threadUrl = href;
        }
        continue;
      }
      if (_isPmLink(href)) {
        // 只有指向具体会话（touid / pmid）的链接才是私信提醒；提醒页顶部
        // 的「消息 / 私信」入口只是站内导航，不能当成一条提醒。
        final peerUid = _touidFromHref(href);
        if (peerUid > 0 || href.contains('pmid=')) {
          isPm = true;
          if (pmUrl.isEmpty) {
            pmUrl = href;
            pmUid = peerUid;
          }
        }
        continue;
      }
      final linkUid = _uidFromHref(href);
      if (linkUid > 0 && uid == 0 && !_noticeNoiseLabels.contains(label)) {
        uid = linkUid;
        userUrl = href;
      }
    }

    var title = raw;
    if (time.isNotEmpty) title = _clean(title.replaceAll(time, ''));
    title = _stripNoticeNoise(title);
    if (title.isEmpty) title = raw;

    // 频道导航（消息 / 我的帖子 / 系统提醒…）既没有正文也没有具体目标，
    // 出现在列表里会让整页只剩一个「消息」入口，点击还会跳去私信列表。
    if (_noticeNavLabels.contains(title) && tid <= 0 && uid <= 0 && pmUid <= 0) {
      return null;
    }

    final NoticeTarget target;
    var url = '';
    if (tid > 0) {
      target = NoticeTarget.thread;
      url = threadUrl;
    } else if (isPm) {
      target = NoticeTarget.pm;
      uid = pmUid > 0 ? pmUid : uid;
      url = pmUrl;
    } else if (uid > 0) {
      target = NoticeTarget.user;
      url = userUrl;
    } else if (title.length >= 3 && !_noticeNoiseLabels.contains(title)) {
      // 没有落地页（系统提醒、插件提醒）：保留正文，界面直接用弹窗展示，
      // 但「查看」这类空壳行仍然丢弃，避免出现整屏没有内容的条目。
      target = NoticeTarget.none;
    } else {
      return null;
    }

    final avatarNode = row.querySelector('img');
    final avatar = avatarNode == null ? '' : _pickImage(avatarNode);
    final unread = row.classes.any((name) => name.contains('new') || name.contains('unread')) ||
        row.querySelector('.new, em.new, .comiis_notice_new') != null;

    return NoticeItem(
      title: title,
      text: '',
      time: time,
      url: _absolute(url),
      kind: view,
      tid: tid,
      uid: uid,
      avatar: target == NoticeTarget.user ? avatar : '',
      unread: unread,
      target: target,
    );
  }

  /// 去掉行尾重复出现的「查看」等操作文字。
  String _stripNoticeNoise(String text) {
    var value = _clean(text);
    var changed = true;
    while (changed) {
      changed = false;
      for (final noise in _noticeNoiseLabels) {
        if (value.length > noise.length && value.endsWith(noise)) {
          value = _clean(value.substring(0, value.length - noise.length));
          changed = true;
        }
      }
    }
    return _clean(value.replaceAll(RegExp(r'[|｜]\s*$'), ''));
  }

  /// 主题编号：兼容 tid=、ptid=（findpost 跳转）与 thread-1-1-1.html。
  int _tidFromHref(String href) {
    final direct = RegExp(r'[?&](?:amp;)?(?:ptid|tid)=(\d+)').firstMatch(href);
    if (direct != null) return _firstInt(direct.group(1)) ?? 0;
    final rewrite = RegExp(r'thread-(\d+)-').firstMatch(href);
    return _firstInt(rewrite?.group(1)) ?? 0;
  }

  bool _isPmLink(String href) =>
      href.contains('do=pm') || href.contains('touid=') || href.contains('ac=pm');

  /// 排行榜：type ∈ member / thread / forum。
  Future<List<(String, String)>> fetchRanking(String type) async {
    final result = await _http.get(
      'misc.php',
      query: {'mod': 'ranklist', 'type': type, 'mobile': '2'},
    );
    _ensureOk(result);
    final doc = parser.parse(result.body);
    final items = <(String, String)>[];
    final rows = doc.querySelectorAll('.comiis_ranklist li, .ranklist li, ol li');
    for (final row in rows) {
      final name = _clean(row.querySelector('a')?.text ?? row.text);
      if (name.isEmpty) continue;
      final value = _clean(
        row.querySelector('.comiis_ranknum, .num, em, span')?.text ?? '',
      ).replaceAll(RegExp(r'^[^\d]*'), '');
      items.add((name, value));
    }
    if (items.isEmpty) {
      for (final a in doc.querySelectorAll('a[href*="uid="], a[href*="thread-"]')) {
        final name = _clean(a.text);
        if (name.isEmpty) continue;
        items.add((name, ''));
      }
    }
    return items;
  }

  /// 标签列表。
  Future<List<(String, int)>> fetchTags() async {
    final result = await _http.get('misc.php', query: {'mod': 'tag', 'mobile': '2'});
    _ensureOk(result);
    final doc = parser.parse(result.body);
    final tags = <(String, int)>[];
    final seen = <int>{};
    for (final a in doc.querySelectorAll('a[href*="mod=tag"]')) {
      final id = int.tryParse(
            RegExp(r'[?&]id=(\d+)').firstMatch(a.attributes['href'] ?? '')?.group(1) ?? '',
          ) ??
          0;
      final name = _clean(a.text);
      if (name.isEmpty || id <= 0 || !seen.add(id)) continue;
      tags.add((name, id));
    }
    return tags;
  }

  /// 标签下的主题列表。
  Future<List<ThreadSummary>> fetchTagThreads(int id, {int page = 1}) => fetchPersonalList(
        'misc.php',
        query: {'mod': 'tag', 'id': '$id', 'mobile': '2', 'page': '$page'},
      );

  /// 每日签到（k_misign 插件）。
  Future<String> signIn() async {
    final home = await _http.get('home.php', query: {'mobile': '2'});
    _ensureOk(home);
    final hash = _findFormhash(home.body);
    if (hash.isEmpty) throw SiteException('请先登录后再签到');
    final result = await _http.get(
      'plugin.php',
      query: {
        'id': 'k_misign:sign',
        'operation': 'qiandao',
        'format': 'button',
        'formhash': hash,
        'mobile': '2',
      },
      referer: AppConfig.uri('home.php', {'mobile': '2'}).toString(),
    );
    _ensureOk(result);
    final text = _clean(result.body);
    if (text.contains('已签到') || text.contains('签到成功') || text.contains('成功')) {
      return text.length <= 40 ? text : '签到成功';
    }
    final msg = _pageMessage(parser.parse(result.body));
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    return text.isEmpty ? '签到完成' : (text.length <= 40 ? text : '签到完成');
  }

  String _threadReferer(int tid) =>
      AppConfig.uri('forum.php', {'mod': 'viewthread', 'tid': '$tid', 'mobile': '2'}).toString();

  Future<String> reply({
    required int tid,
    required int fid,
    required String formhash,
    required String message,
    int? replyToPid,
    String noticeAuthor = '',
    String noticeTrim = '',
    String noticeAuthorMsg = '',
    List<int> attachmentIds = const [],
    bool useSignature = true,
  }) async {
    final query = <String, String>{
      'mod': 'post',
      'action': 'reply',
      'fid': '$fid',
      'tid': '$tid',
      'replysubmit': 'yes',
      'mobile': '2',
    };
    if (replyToPid != null && replyToPid > 0) {
      // 手机版网页回复某一楼用的就是 repquote；reppost 只发提醒、不动正文，
      // 用它发出来就是一条看不出对象的独立回复。
      query['repquote'] = '$replyToPid';
    }
    final response = await _http.post(
      'forum.php',
      referer: AppConfig.uri('forum.php', {'mod': 'viewthread', 'tid': '$tid', 'mobile': '2'}).toString(),
      query: query,
      form: {
        'formhash': formhash,
        'message': message,
        // 服务端会把 noticetrimstr 拼在正文最前面，就是网页端那个灰色引用框。
        if (noticeTrim.isNotEmpty) 'noticetrimstr': noticeTrim,
        if (noticeAuthor.isNotEmpty) 'noticeauthor': noticeAuthor,
        if (noticeAuthorMsg.isNotEmpty) 'noticeauthormsg': noticeAuthorMsg,
        'posttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
        'usesig': useSignature ? '1' : '0',
        for (final aid in attachmentIds) 'attachnew[$aid][description]': '',
      },
    );
    final doc = parser.parse(response.body);
    // 「需要审核」里带「审核」二字，会被错误关键词命中；先认它，别当成失败抛出去。
    if (response.body.contains('需要审核') || response.body.contains('审核通过')) {
      return '回复已提交，等待审核通过';
    }
    final msg = _pageMessage(doc);
    // 已经回到帖子页说明服务端收下了，页面上的站点提示不算拒绝。
    if (msg != null && _looksLikeError(msg) && !_landedOnThread(response)) {
      throw SiteException(msg);
    }
    return '回复成功';
  }

  /// 取回复页上服务端算好的引用凭证（`noticeauthor` / `noticetrimstr`）。
  ///
  /// 这两个值带 `authcode()` 加密，客户端算不出来；取不到时返回空对象，
  /// 上层用本地兜底格式，不影响回复本身发出去。
  Future<ReplyContext> fetchReplyContext({
    required int tid,
    required int fid,
    int? pid,
  }) async {
    final query = <String, String>{
      'mod': 'post',
      'action': 'reply',
      'fid': '$fid',
      'tid': '$tid',
      'mobile': '2',
    };
    if (pid != null && pid > 0) query['repquote'] = '$pid';
    try {
      final page = await _http.get('forum.php', query: query);
      if (page.statusCode >= 400) return ReplyContext.empty;
      return ReplyContext.fromHtml(page.body);
    } catch (_) {
      return ReplyContext.empty;
    }
  }

  /// 楼中楼点评：Discuz 的 `action=comment`，直接挂在指定楼层下。
  Future<String> addComment({
    required int tid,
    required int pid,
    required String message,
    required String formhash,
  }) async {
    if (formhash.isEmpty) throw SiteException('点评凭证已失效，请下拉刷新后重试');
    final response = await _http.post(
      'forum.php',
      referer: AppConfig.uri('forum.php', {'mod': 'viewthread', 'tid': '$tid', 'mobile': '2'}).toString(),
      query: {
        'mod': 'post',
        'action': 'comment',
        'tid': '$tid',
        'pid': '$pid',
        'commentsubmit': 'yes',
        'mobile': '2',
      },
      form: {
        'formhash': formhash,
        'message': message,
        'posttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      },
    );
    final msg = _pageMessage(parser.parse(response.body));
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    return '点评成功';
  }

  Future<String> createThread({
    required int fid,
    required String subject,
    required String message,
    String formhash = '',
    List<int> attachmentIds = const [],
    List<PendingUpload> pendingFiles = const [],
    bool replyOnly = false,
    bool orderDesc = false,
    bool notify = false,
    bool useSignature = true,
    bool poll = false,
    List<String> pollOptions = const [],
    bool pollMultiple = false,
    String tags = '',
    String readPerm = '',
    String price = '',
  }) async {
    var hash = formhash;
    if (hash.isEmpty) {
      final page = await _http.get(
        'forum.php',
        query: {
          'mod': 'post',
          'action': 'newthread',
          'fid': '$fid',
          if (poll) 'special': '1',
          'mobile': '2',
        },
      );
      _ensureOk(page);
      hash = _findFormhash(page.body);
    }
    if (hash.isEmpty) {
      throw SiteException('无法进入发帖页面');
    }

    final form = <String, String>{
      'formhash': hash,
      'posttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'wysiwyg': '1',
      'subject': subject,
      'message': message,
      'tags': tags,
      'usesig': useSignature ? '1' : '0',
      if (readPerm.isNotEmpty && readPerm != '0') 'readperm': readPerm,
      if (price.isNotEmpty && price != '0') 'price': price,
      if (replyOnly) 'replyonly': '1',
      if (orderDesc) 'ordertype': '1',
      if (notify) 'emailnotify': '1',
      if (poll) ...{
        'polloptions': pollOptions.join('\n'),
        'pollmultiple': pollMultiple ? '1' : '0',
        'maxselect': pollMultiple ? '${pollOptions.length}' : '1',
      },
      for (final aid in attachmentIds) 'attachnew[$aid][description]': '',
      'save': '',
    };
    final referer = AppConfig.uri('forum.php', {
      'mod': 'post',
      'action': 'newthread',
      'fid': '$fid',
      if (poll) 'special': '1',
      'mobile': '2',
    }).toString();
    final HttpResult response;
    if (pendingFiles.isNotEmpty) {
      // 没有 swfupload 凭证时，照网页的做法把文件塞进发帖表单一起提交。
      // 手机模板的表单本身就是 multipart + `Filedata`，服务端按同一套逻辑收。
      response = await _http.postFile(
        'forum.php',
        query: {
          'mod': 'post',
          'action': 'newthread',
          'fid': '$fid',
          'topicsubmit': 'yes',
          if (poll) 'special': '1',
          'mobile': '2',
        },
        field: pendingFiles.first.field,
        filename: pendingFiles.first.filename,
        bytes: pendingFiles.first.bytes,
        // 多选了几张图时全部带上，字段名重复出现即可（网页端表单就是这样）。
        extraFiles: [
          for (final file in pendingFiles.skip(1))
            HttpUploadFile(filename: file.filename, bytes: file.bytes),
        ],
        fields: form,
        referer: referer,
      );
    } else {
      response = await _http.post(
        'forum.php',
        referer: referer,
        query: {
          'mod': 'post',
          'action': 'newthread',
          'fid': '$fid',
          'topicsubmit': 'yes',
          if (poll) 'special': '1',
          'mobile': '2',
        },
        form: form,
      );
    }
    final doc = parser.parse(response.body);
    // 「需要审核」自带「审核」二字，会被错误关键词命中，先按成功处理。
    if (response.body.contains('需要审核') || response.body.contains('审核通过')) {
      return '主题已提交，等待审核通过';
    }
    final msg = _pageMessage(doc);
    if (msg != null && _looksLikeError(msg) && !_landedOnThread(response)) {
      throw SiteException(msg);
    }
    final tid = RegExp(r'thread-(\d+)-1-1\.html').firstMatch(response.uri.toString())?.group(1);
    return tid == null ? '发布成功' : '发布成功，主题 ID $tid';
  }

  Future<String> addFavorite({required int tid, required String formhash}) async {
    final response = await _http.post(
      'home.php',
      referer: AppConfig.uri('forum.php', {'mod': 'viewthread', 'tid': '$tid', 'mobile': '2'}).toString(),
      query: {
        'mod': 'spacecp',
        'ac': 'favorite',
        'type': 'thread',
        'id': '$tid',
        'favoritesubmit': 'yes',
        'formhash': formhash,
        'handlekey': 'favorite',
        'mobile': '2',
      },
      form: {'formhash': formhash, 'description': ''},
    );
    final doc = parser.parse(response.body);
    final msg = _pageMessage(doc);
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    return msg == null || msg.length > 40 ? '已加入收藏' : msg;
  }

  /// 收藏 / 取消收藏。
  ///
  /// Discuz 的取消收藏必须 POST 提交 deletesubmit；X3.4 支持直接按 tid 定位收藏，
  /// 老版本再退回收藏夹里的 favid。
  Future<String> toggleFavorite({
    required int tid,
    required String formhash,
    required bool favorited,
    String href = '',
  }) async {
    if (!favorited) {
      try {
        return await addFavorite(tid: tid, formhash: formhash);
      } catch (e) {
        final message = e is SiteException ? e.message : '';
        if (message.contains('重复收藏') || message.contains('已经收藏') || message.contains('收藏过')) {
          return '该主题已在收藏中';
        }
        rethrow;
      }
    }

    var message = await _deleteFavorite(tid: tid, formhash: formhash);
    if (!await _favoriteExists(tid)) return '已取消收藏';

    // 兼容旧版：从收藏夹里取真实 favid 后再删一次。
    var favid = await _findFavoriteFavid(tid);
    if (favid.isEmpty) favid = RegExp(r'favid=(\d+)').firstMatch(href)?.group(1) ?? '';
    if (favid.isNotEmpty) {
      message = await _deleteFavorite(tid: tid, formhash: formhash, favid: favid) ?? message;
    }
    if (await _favoriteExists(tid)) {
      throw SiteException(message ?? '取消收藏失败，请稍后重试');
    }
    return '已取消收藏';
  }

  /// 提交删除收藏；返回页面提示（失败时用于告知用户）。
  Future<String?> _deleteFavorite({
    required int tid,
    required String formhash,
    String favid = '',
  }) async {
    final target = <String, String>{};
    if (favid.isEmpty) {
      target['id'] = '$tid';
    } else {
      target['favid'] = favid;
    }
    final result = await _http.post(
      'home.php',
      query: {
        'mod': 'spacecp',
        'ac': 'favorite',
        'op': 'delete',
        'type': 'thread',
        ...target,
        'formhash': formhash,
        'deletesubmit': 'yes',
        'handlekey': 'favorite',
        'mobile': '2',
      },
      form: {'formhash': formhash, 'deletesubmit': 'yes', ...target},
      referer: AppConfig.uri('home.php', {'mod': 'space', 'do': 'favorite', 'view': 'me'}).toString(),
    );
    _ensureOk(result);
    final message = _pageMessage(parser.parse(result.body));
    if (message != null && _looksLikeError(message) && !message.contains('不存在')) {
      throw SiteException(message);
    }
    return message;
  }

  /// 打开删除确认页：仍能打开说明该主题还在收藏夹里。
  Future<bool> _favoriteExists(int tid) async {
    final result = await _http.get(
      'home.php',
      query: {
        'mod': 'spacecp',
        'ac': 'favorite',
        'op': 'delete',
        'type': 'thread',
        'id': '$tid',
        'handlekey': 'favorite',
        'mobile': '2',
      },
    );
    _ensureOk(result);
    final doc = parser.parse(result.body);
    return doc.querySelector('input[name="deletesubmit"]') != null ||
        doc.querySelector('form[id^="favoriteform_"]') != null ||
        result.body.contains('name="deletesubmit"');
  }

  /// 在收藏夹中按主题 tid 定位 favid；找不到返回空串。
  Future<String> _findFavoriteFavid(int tid) async {
    for (final userAgent in <String?>[_desktopUserAgent, null]) {
      for (var page = 1; page <= 3; page++) {
        final body = await _favoritePage(page, userAgent);
        if (!body.contains('favid=') && !body.contains('favorite[]')) break;
        final doc = parser.parse(body);
        for (final marker in _favoriteMarkers(doc)) {
          final favid = _favoriteMarkerFavid(marker);
          if (favid == null) continue;
          if (_favoriteRowHasThread(marker, tid)) return favid;
        }
      }
    }
    return '';
  }

  /// 收藏项里的 favid 标记：删除链接或批量删除复选框。
  Iterable<Element> _favoriteMarkers(Document doc) sync* {
    yield* doc.querySelectorAll('a[href*="favid="]');
    yield* doc.querySelectorAll('input[type="checkbox"][name*="favorite"]');
  }

  String? _favoriteMarkerFavid(Element marker) {
    final href = marker.attributes['href'] ?? '';
    final fromHref = RegExp(r'favid=(\d+)').firstMatch(href)?.group(1);
    if (fromHref != null) return fromHref;
    final value = marker.attributes['value'] ?? '';
    return RegExp(r'^\d+$').hasMatch(value) ? value : null;
  }

  Future<String> _favoritePage(int page, String? userAgent) async {
    final result = await _http.get(
      'home.php',
      query: {'mod': 'space', 'do': 'favorite', 'view': 'me', 'type': 'thread', 'page': '$page'},
      userAgent: userAgent,
    );
    _ensureOk(result);
    return result.body;
  }

  /// 从收藏项内的标记（删除链接 / 复选框）向上找到行容器，判断该行收藏的主题是否为 tid。
  bool _favoriteRowHasThread(Element marker, int tid) {
    Element? node = marker;
    for (var depth = 0; depth < 10 && node != null; depth++) {
      if (_containsThreadHref(node, tid)) return true;
      // 出现别的主题说明已经越过当前收藏项。
      if (_containsOtherThreadHref(node, tid)) return false;
      node = node.parent;
    }
    return false;
  }

  bool _containsThreadHref(Element node, int tid) {
    for (final a in node.querySelectorAll('a[href]')) {
      final match = RegExp(r'(?:tid=|thread-)(\d+)').firstMatch(a.attributes['href'] ?? '');
      if (match != null && int.tryParse(match.group(1)!) == tid) return true;
    }
    return false;
  }

  bool _containsOtherThreadHref(Element node, int tid) {
    for (final a in node.querySelectorAll('a[href]')) {
      final match = RegExp(r'(?:tid=|thread-)(\d+)').firstMatch(a.attributes['href'] ?? '');
      if (match != null && int.tryParse(match.group(1)!) != tid) return true;
    }
    return false;
  }

  /// Discuz 原生搜索：formhash -> POST 关键词 -> searchid 翻页。
  Future<List<ThreadSummary>> search(
    String keyword, {
    int fid = 0,
    int page = 1,
    int maxPages = 10,
  }) async {
    final landing = await _http.get('search.php', query: {'mod': 'forum', 'mobile': '2'});
    _ensureOk(landing);
    final formHash = _findFormhash(landing.body);
    if (formHash.isEmpty) {
      throw SiteException(_pageMessage(parser.parse(landing.body)) ?? '搜索需要登录，请先登录');
    }

    // 每次分页请求都重新获取 searchid，避免依赖已过期的 Discuz 搜索会话。
    final response = await _http.post(
      'search.php',
      referer: AppConfig.uri('search.php', {'mod': 'forum', 'mobile': '2'}).toString(),
      query: {'mod': 'forum', 'mobile': '2'},
      form: {
        'formhash': formHash,
        'srchtxt': keyword,
        'searchsubmit': 'yes',
        if (fid > 0) 'srchfid[]': '$fid',
      },
    );
    final sid = RegExp(r'searchid=(\d+)').firstMatch(response.body)?.group(1);
    if (sid == null) {
      final items = _parseThreadList(response.body);
      if (items.isNotEmpty) return items;
      final loose = _parseLooseThreads(response.body);
      if (loose.isNotEmpty) return loose;
      throw SiteException(_pageMessage(parser.parse(response.body)) ?? '没有找到相关帖子');
    }

    final results = <ThreadSummary>[];
    final seen = <int>{};
    final lastPage = page + maxPages - 1;
    for (var pageNo = page; pageNo <= lastPage; pageNo++) {
      final result = await _http.get(
        'search.php',
        query: {
          'mod': 'forum',
          'searchid': sid,
          'orderby': 'lastpost',
          'ascdesc': 'desc',
          'searchsubmit': 'yes',
          'kw': keyword,
          'mobile': '2',
          'page': '$pageNo',
        },
      );
      _ensureOk(result);
      var items = _parseThreadList(result.body);
      // 搜索结果模板不一定使用首页列表的 li.forumlist_li 结构，解析不到时用宽松规则兜底。
      if (items.isEmpty) items = _parseLooseThreads(result.body);
      if (items.isEmpty) break;
      for (final item in items) {
        if (seen.add(item.tid)) results.add(item);
      }
      if (items.length < AppConfig.pageSize) break;
    }
    return results;
  }

  // ---------------------------------------------------------------- 解析

  /// 解析主题列表（测试用）。
  @visibleForTesting
  static List<ThreadSummary> parseThreadListForTest(String html, {void Function(int raw)? onRaw}) =>
      ForumRepository.instance._parseThreadList(html, onRaw: onRaw);

  /// 宽松解析（测试用）。
  @visibleForTesting
  static List<ThreadSummary> parseLooseThreadsForTest(String html, {void Function(int raw)? onRaw}) =>
      ForumRepository.instance._parseLooseThreads(html, onRaw: onRaw);

  /// 解析主题列表。
  ///
  /// [onRaw] 回传「页面上本来有多少条」——回收站主题会被跳过，
  /// 调用方拿这个数字和返回长度一比就知道有没有被筛掉，用于补页。
  List<ThreadSummary> _parseThreadList(String html, {void Function(int raw)? onRaw}) {
    final doc = parser.parse(html);
    final items = <ThreadSummary>[];
    var raw = 0;
    for (final li in doc.querySelectorAll('li.forumlist_li')) {
      final titleLink = li.querySelector('.mmlist_li_box h2 a[href*="thread-"]') ??
          li.querySelector('.mmlist_li_box a[href*="thread-"]');
      if (titleLink == null) continue;
      raw++;
      // 已删除的帖子（回收站）在列表里只剩个空壳，点进去也看不到内容。
      if (_isRecycledThread(li, titleLink)) continue;
      final href = titleLink.attributes['href'] ?? '';
      final tid = _firstInt(RegExp(r'thread-(\d+)').firstMatch(href)?.group(1));
      if (tid == null) continue;

      final images = <String>[];
      for (final img in li.querySelectorAll('img.comiis_loadimages, .comiis_pyqlist_imgs img')) {
        final src = _pickImage(img);
        if (src.isNotEmpty && !images.contains(src)) images.add(src);
      }

      final numbers = <int>[];
      for (final span in li.querySelectorAll('.comiis_xznalist_bottom span.comiis_tm')) {
        final value = int.tryParse(_clean(span.text));
        if (value != null) numbers.add(value);
      }

      items.add(ThreadSummary(
        tid: tid,
        title: _clean(titleLink.text),
        url: _absolute(href),
        excerpt: _clean(li.querySelector('.list_body')?.text ?? ''),
        author: _clean(li.querySelector('.top_user')?.text ?? ''),
        avatar: _postAvatar(li),
        uid: _postUid(li),
        time: _clean(li.querySelector('.forumlist_li_time')?.text ?? ''),
        boardName: _clean(li.querySelector('.comiis_xznalist_bk a')?.text ?? ''),
        images: images.take(3).toList(),
        replies: numbers.length >= 2 ? numbers[1] : 0,
        views: numbers.length >= 3 ? numbers[2] : 0,
      ));
    }
    onRaw?.call(raw);
    return items;
  }

  /// 这条是不是回收站里的主题（被用户/管理删掉的）。
  ///
  /// 三种标记都认，因为各套模板写法不同：标题前缀、链接上的 `recy`
  /// 类名、列表项里独立的「回收站」小标签。
  bool _isRecycledThread(Element li, Element titleLink) {
    if (RecycleBin.hasTitlePrefix(_clean(titleLink.text))) return true;
    if (RecycleBin.hasRecyClass(_classes(titleLink))) return true;
    if (RecycleBin.hasRecyClass(_classes(li))) return true;
    for (final tag in li.querySelectorAll('span, em, i, b, strong, label')) {
      if (RecycleBin.isLabel(tag.text)) return true;
    }
    return false;
  }

  /// 元素的 class 拆分。没有 class 属性时返回空集合，不用到处判空。
  Iterable<String> _classes(Element element) =>
      (element.attributes['class'] ?? '').split(RegExp(r'\s+')).where((e) => e.isNotEmpty);

  /// 兜底：从任意页面提取主题链接（个人中心、收藏页等）。
  List<ThreadSummary> _parseLooseThreads(String html, {void Function(int raw)? onRaw}) {
    final doc = parser.parse(html);
    final items = <ThreadSummary>[];
    final seen = <int>{};
    var raw = 0;
    for (final a in doc.querySelectorAll('a[href*="thread-"]')) {
      final text = _clean(a.text);
      if (text.length < 4) continue;
      final tid = _firstInt(RegExp(r'thread-(\d+)').firstMatch(a.attributes['href'] ?? '')?.group(1));
      if (tid == null || !seen.add(tid)) continue;
      raw++;
      if (RecycleBin.hasTitlePrefix(text) || RecycleBin.hasRecyClass(_classes(a))) continue;
      final container = a.parent?.parent ?? a.parent;
      items.add(ThreadSummary(
        tid: tid,
        title: text,
        url: _absolute(a.attributes['href']),
        excerpt: _clean(container?.querySelector('.list_body')?.text ?? ''),
        author: _clean(container?.querySelector('.top_user')?.text ?? ''),
        avatar: container == null ? '' : _postAvatar(container),
        uid: container == null ? 0 : _postUid(container),
        time: _clean(container?.querySelector('.comiis_postli_times, .forumlist_li_time')?.text ?? ''),
        boardName: _clean(container?.querySelector('.comiis_xznalist_bk a')?.text ?? ''),
      ));
    }
    onRaw?.call(raw);
    return items;
  }

  /// 个人空间回复列表（`type=reply`）：标题走 findpost 链接，
  /// 桌面模板另有一行 `<td class="xg1">` 存放回复正文摘要。
  List<ThreadSummary> _parseSpaceReplies(String html) {
    final doc = parser.parse(html);

    // pid -> 回复正文摘要。
    final excerpts = <int, String>{};
    for (final cell in doc.querySelectorAll('td.xg1')) {
      final link = cell.querySelector('a[href*="goto=findpost"]');
      if (link == null) continue;
      final pid = _firstInt(RegExp(r'pid=(\d+)').firstMatch(link.attributes['href'] ?? '')?.group(1));
      final text = _clean(link.text);
      if (pid == null || text.isEmpty || text == '......') continue;
      excerpts.putIfAbsent(pid, () => text);
    }

    final items = <ThreadSummary>[];
    final seen = <int>{};

    // 桌面模板：回复标题固定在 <th> 内，避免误取页面其它 findpost 跳转链接。
    final anchors = <Element>[];
    for (final row in doc.querySelectorAll('#delform tr')) {
      final link = row.querySelector('th a[href*="goto=findpost"]');
      if (link != null) anchors.add(link);
    }
    // 移动模板：<div class="bm_c"><a href="...goto=findpost...">标题</a></div>。
    if (anchors.isEmpty) {
      for (final anchor in doc.querySelectorAll('a[href*="goto=findpost"]')) {
        if (anchor.parent?.classes.contains('xg1') == true) continue;
        anchors.add(anchor);
      }
    }

    for (final anchor in anchors) {
      final href = anchor.attributes['href'] ?? '';
      final tid = _firstInt(RegExp(r'ptid=(\d+)').firstMatch(href)?.group(1)) ??
          _firstInt(RegExp(r'[?&]tid=(\d+)').firstMatch(href)?.group(1));
      if (tid == null || tid <= 0 || !seen.add(tid)) continue;
      final title = _clean(anchor.text);
      if (title.isEmpty) continue;
      final pid = _firstInt(RegExp(r'pid=(\d+)').firstMatch(href)?.group(1)) ?? 0;
      final row = anchor.parent?.parent;
      items.add(ThreadSummary(
        tid: tid,
        title: title,
        url: _absolute(href),
        excerpt: excerpts[pid] ?? '',
        boardName: _clean(row?.querySelector('td a[href*="mod=forumdisplay"]')?.text ?? ''),
      ));
    }
    return items;
  }

  /// 楼层作者 uid：优先取作者名 / 头像链接，再退回到楼层内任意资料链接。
  int _postUid(Element el) {
    final hrefs = <String?>[
      el.querySelector('a.top_user')?.attributes['href'],
      el.querySelector('a.postli_top_tximg')?.attributes['href'],
      el.querySelector('img.top_tximg')?.attributes['src'],
      el.querySelector('a[href*="mod=space"][href*="uid="]')?.attributes['href'],
      el.querySelector('a[href*="uid="]')?.attributes['href'],
      el.querySelector('[data-uid]')?.attributes['data-uid'],
    ];
    for (final href in hrefs) {
      final raw = (href ?? '').trim();
      if (raw.isEmpty) continue;
      final match = RegExp(r'[?&]uid=(\d+)').firstMatch(raw);
      final uid = int.tryParse(match?.group(1) ?? raw) ?? 0;
      if (uid > 0) return uid;
      // 静态头像路径 .../data/avatar/000/02/55/71_avatar_middle.jpg 里也带着 uid。
      final path = RegExp(r'data/avatar/(\d{3})/(\d{2})/(\d{2})/(\d{2})_').firstMatch(raw);
      if (path != null) {
        final fromPath = int.tryParse(
          '${path.group(1)}${path.group(2)}${path.group(3)}${path.group(4)}',
        );
        if (fromPath != null && fromPath > 0) return fromPath;
      }
    }
    final match = RegExp(r'''authorid[=:"']\s*(\d+)''').firstMatch(el.innerHtml);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  /// 楼层头像：兼容普通头像、懒加载属性与背景图三种写法。
  String _postAvatar(Element el) {
    final img = el.querySelector('img.top_tximg') ??
        el.querySelector('.postli_top_tximg img') ??
        el.querySelector('img[class*="tximg"]') ??
        el.querySelector('a[href*="uid="] img') ??
        el.querySelector('img[src*="/avatar/"]');
    for (final attr in const ['src', 'data-src', 'data-original', 'file']) {
      final value = (img?.attributes[attr] ?? '').trim();
      if (value.isEmpty || _isPlaceholderImage(value)) continue;
      return _absolute(value);
    }
    final link = el.querySelector('a.postli_top_tximg') ?? el.querySelector('.comiis_postli_top a');
    final style = link?.attributes['style'] ?? '';
    final background = RegExp(r'''url\(["']?([^)"']+)["']?\)''').firstMatch(style)?.group(1) ?? '';
    if (background.isNotEmpty && !_isPlaceholderImage(background)) return _absolute(background);
    return '';
  }

  bool _isPlaceholderImage(String url) {
    final value = url.toLowerCase();
    return value.contains('none.gif') ||
        value.contains('none.png') ||
        value.contains('imageloading') ||
        value.contains('avatar_bg') ||
        // uid=0 的头像地址会被服务端当成「当前登录用户」，必须丢弃后按 uid 重新拼接。
        RegExp(r'[?&]uid=0(?:&|$)').hasMatch(value);
  }

  String _pickImage(Element img) {
    const lazyAttrs = [
      'comiis_loadimages',
      'data-src',
      'data-original',
      'file',
      'zoomfile',
      'longdesc',
    ];
    String valueOf(String attr) => (img.attributes[attr] ?? '').trim();
    bool usable(String value) =>
        value.isNotEmpty &&
        !value.contains('none.png') &&
        !value.contains('none.gif') &&
        !value.contains('imageloading.gif') &&
        !value.contains('noavatar');

    for (final attr in lazyAttrs) {
      final value = valueOf(attr);
      if (usable(value)) return _absolute(value);
    }
    final src = valueOf('src');
    return usable(src) ? _absolute(src) : '';
  }

  /// 删掉楼层正文顶上那行 `Re: 主题名`。
  ///
  /// Discuz 给每条回复都存了 subject：编辑过的回复会被写成 `Re: 主题`，
  /// 网页端在正文上方渲染成一行标题。App 里这行只是噪声——正文就在下面，
  /// 而早先编辑回复时还把 `Re: 标题` 当 subject 提交，等于自己把数据写脏了。
  @visibleForTesting
  static void removeFloorSubject(Element content) {
    final head = content.children.isEmpty ? null : content.children.first;
    if (head != null && _isFloorSubject(head)) {
      head.remove();
      return;
    }
    for (final node in content.querySelectorAll('.comiis_subject, .comiis_postli_subject')) {
      node.remove();
    }
  }

  static bool _isFloorSubject(Element node) {
    const headings = <String>{'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};
    final cls = (node.attributes['class'] ?? '').toLowerCase();
    if (!headings.contains(node.localName) && !cls.contains('subject')) return false;
    // 只认「Re: 主题」这种回复标题；正文里自己写的小标题不动。
    return RegExp(r'^re\s*[:：]\s*\S', caseSensitive: false).hasMatch(_clean(node.text));
  }

  String _sanitize(String html) {
    var output = html
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'\son[a-z]+\s*=\s*"[^"]*"', caseSensitive: false), '')
        .replaceAll(RegExp(r"\son[a-z]+\s*=\s*'[^']*'", caseSensitive: false), '');

    final doc = parser.parseFragment(output);
    for (final img in doc.querySelectorAll('img')) {
      final src = _pickImage(img);
      img.attributes['src'] = src;
      if (src.isEmpty) {
        img.attributes['data-empty'] = '1';
      }
      final width = img.attributes['width'];
      final height = img.attributes['height'];
      if (width == '0' || width == '1') img.attributes.remove('width');
      if (height == '0' || height == '1') img.attributes.remove('height');
      img.attributes.remove('comiis_loadimages');
      img.attributes.remove('data-src');
      img.attributes.remove('data-original');
      img.attributes.remove('zoomfile');
      img.attributes.remove('longdesc');
    }
    for (final a in doc.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      if (href.startsWith('javascript:')) {
        a.attributes['href'] = '#';
      } else if (href.isNotEmpty) {
        a.attributes['href'] = _absolute(href);
      }
    }
    return doc.outerHtml;
  }

  // ---------------------------------------------------------------- 工具

  static String _findFormhash(String html) {
    final patterns = [
      RegExp(r'''name=["']formhash["'][^>]*?value=["']([0-9a-zA-Z]+)["']''', caseSensitive: false),
      RegExp(r'''value=["']([0-9a-zA-Z]+)["'][^>]*?name=["']formhash["']''', caseSensitive: false),
      RegExp(r'''formhash\s*[=:]\s*["']([0-9a-zA-Z]+)["']''', caseSensitive: false),
      RegExp(r'formhash=([0-9a-zA-Z]{8})', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) return match.group(1)!;
    }
    return '';
  }

  bool _isLoggedInHtml(String html) {
    final match = RegExp(r"discuz_uid\s*=\s*'(\d+)'").firstMatch(html);
    return match != null && match.group(1) != '0';
  }

  int _intOf(String? text) =>
      int.tryParse(_clean(text ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  String _uploadMessage(int status) => switch (status) {
        1 || 4 => '不支持此类扩展名的文件',
        2 || 3 || 5 => '文件超过服务器允许的大小',
        6 || 11 => '今日已无法上传更多附件',
        7 => '请选择图片文件',
        8 => '附件文件无法保存',
        9 => '没有合法的文件被上传',
        10 => '非法操作，请重新登录后再试',
        _ => '上传失败，请稍后重试',
      };

  static String? _pageMessage(Document doc) {
    for (final selector in [
      '.comiis_message_table',
      '.alert_info',
      '.alert_error',
      '.showmessage',
      '#messagetext p',
      '.comiis_tip',
    ]) {
      final text = _clean(doc.querySelector(selector)?.text ?? '');
      // 编辑记录也放在 `.alert_info` 里，不能当提示返回。
      if (text.isEmpty || text.length >= 800 || isEditNote(text)) continue;
      return text;
    }
    return null;
  }

  bool _looksLikeError(String text) =>
      RegExp(r'(抱歉|错误|失败|不能|无权|权限|非法|灌水|间隔|禁止|审核|登录)').hasMatch(text);

  void _ensureOk(HttpResult result) {
    if (result.statusCode >= 400) {
      final doc = parser.parse(result.body);
      final message = _pageMessage(doc);
      throw SiteException(message ?? '站点返回错误（${result.statusCode}）', code: result.statusCode);
    }
  }

  int? _firstInt(String? value) => value == null ? null : int.tryParse(value);

  static String _clean(String text) => text
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// 取可见文本：跳过 script / style 等源码节点，保留换行。
  /// 插件页面常把内联脚本写在正文容器里，直接取 `.text` 会把源码当成正文。
  String _visibleText(Element? root, {int limit = 1600}) {
    if (root == null) return '';
    const skipped = {'script', 'style', 'noscript', 'iframe', 'link', 'meta', 'template', 'head'};
    const blocks = {
      'p', 'div', 'li', 'tr', 'br', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'table', 'section', 'ul', 'ol', 'dd', 'dt', 'td', 'th',
    };
    final buffer = StringBuffer();
    var truncated = false;

    void walk(Node node) {
      if (truncated) return;
      if (node is Element) {
        final tag = node.localName?.toLowerCase() ?? '';
        if (skipped.contains(tag)) return;
        final isBlock = blocks.contains(tag);
        if (isBlock) buffer.write('\n');
        for (final child in node.nodes) {
          walk(child);
          if (buffer.length > limit * 4) {
            truncated = true;
            return;
          }
        }
        if (isBlock) buffer.write('\n');
        return;
      }
      if (node is Text) buffer.write(node.text);
    }

    walk(root);
    final lines = buffer
        .toString()
        .replaceAll('\r', '')
        .replaceAll('\u00a0', ' ')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final text = lines.join('\n');
    return text.length > limit ? '${text.substring(0, limit)}…' : text;
  }

  String _absolute(String? url) {
    final value = (url ?? '').trim();
    if (value.isEmpty) return '';
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    return AppConfig.uri(value).toString();
  }

  /// 解析站点输出的时间（`2026/12/31 02:52:00`、`2026-12-31 02:52:00`）。
  DateTime? _parseSiteDate(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final match = RegExp(
      r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})(?:\s+|T)(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?',
    ).firstMatch(value);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.tryParse(match.group(6) ?? '') ?? 0,
    );
  }

  /// 读取页面 JS 里的 `var etime = new Date('...')`。
  DateTime? _jsDate(String html, String name) {
    final match = RegExp(
      'var\\s+$name\\s*=\\s*new\\s+Date\\(\\s*["\']([^"\']+)["\']\\s*\\)',
    ).firstMatch(html);
    return _parseSiteDate(match?.group(1));
  }

  String? _attrIgnoreCase(Element element, String name) {
    final target = name.toLowerCase();
    for (final entry in element.attributes.entries) {
      if (entry.key.toString().toLowerCase() == target) return entry.value;
    }
    return null;
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  /// 商城列表里的剩余时间文案（站点自身只输出 00 天 00 小时占位）。
  String _mallTimeLabel(Element? element) {
    if (element == null) return '';
    final start = _parseSiteDate(_attrIgnoreCase(element, 'startTime'));
    final end = _parseSiteDate(_attrIgnoreCase(element, 'endTime'));
    final now = DateTime.now();
    if (start != null && now.isBefore(start)) {
      return '${start.month}月${start.day}日 ${_two(start.hour)}:${_two(start.minute)} 开抢';
    }
    if (end == null) return '';
    final left = end.difference(now);
    if (left.isNegative) return '已结束';
    return '剩余 ${left.inDays}天${_two(left.inHours % 24)}小时'
        '${_two(left.inMinutes % 60)}分${_two(left.inSeconds % 60)}秒';
  }

  String _avatarForUid(int uid) {
    final padded = uid.toString().padLeft(9, '0');
    return 'https://cdn.binmt.cc/uc_server/data/avatar/'
        '${padded.substring(0, 3)}/${padded.substring(3, 5)}/${padded.substring(5, 7)}/${padded.substring(7, 9)}_avatar_middle.jpg';
  }

  /// 解析个人空间页（`home.php?mod=space&do=profile` 的 comiis 移动模板）。
  UserProfile _parseSpaceProfile(Document doc, String html, {int uid = 0, String fallbackName = ''}) {
    final info = doc.querySelector('.comiis_space_info') ??
        doc.querySelector('.comiis_space_tx') ??
        doc.querySelector('.comiis_space_center');

    final resolvedUid = uid > 0
        ? uid
        : _firstInt(
              RegExp(r"discuz_uid\s*=\s*'(\d+)'").firstMatch(html)?.group(1) ??
                  RegExp(r'[?&]uid=(\d+)').firstMatch(html)?.group(1) ??
                  '0',
            ) ??
            0;

    var name = _clean(
      info?.querySelector('h2')?.text ??
          doc.querySelector('h2.fyy')?.text ??
          doc.querySelector('.comiis_space_name')?.text ??
          doc.querySelector('.top_user')?.text ??
          RegExp(r"username\s*=\s*'([^']*)'").firstMatch(html)?.group(1) ??
          '',
    );
    if (name.isEmpty) name = fallbackName;

    final rawAvatar = _absolute(
      info?.querySelector('.user_img img')?.attributes['src'] ??
          doc.querySelector('.comiis_space_tximg img')?.attributes['src'] ??
          doc.querySelector('.user_img img')?.attributes['src'],
    );
    // 页面顶部可能混入当前登录用户的头像，必须校验 uid 才能采用。
    var avatar = rawAvatar;
    if (resolvedUid > 0) {
      if (_avatarMatchesUid(rawAvatar, resolvedUid)) {
        avatar = rawAvatar;
      } else if (rawAvatar.toLowerCase().contains('noavatar')) {
        avatar = rawAvatar;
      } else {
        avatar = _avatarForUid(resolvedUid);
      }
    } else if (_isPlaceholderImage(avatar)) {
      avatar = '';
    }

    // 统计区：<span>帖子 45</span> / <span>回复 2988</span> / <span>粉丝 16</span>。
    final counts = <String, String>{};
    for (final span in doc.querySelectorAll('ul li span, .comiis_space_num span')) {
      final text = _clean(span.text);
      final match = RegExp(r'^(.{1,4}?)\s*(\d+)$').firstMatch(text);
      if (match == null) continue;
      counts.putIfAbsent(_clean(match.group(1)!), () => match.group(2)!);
    }
    // 积分区：<li><span>4083</span>金币</li>。
    for (final li in doc.querySelectorAll('ul li')) {
      final label = _clean(li.text).replaceAll(RegExp(r'[0-9\s]'), '');
      final number = _clean(li.querySelector('span')?.text ?? '').replaceAll(RegExp(r'[^0-9]'), '');
      if (label.isEmpty || label.length > 4 || number.isEmpty) continue;
      counts.putIfAbsent(label, () => number);
    }

    final bodyText = _clean(doc.body?.text ?? '');
    final level = _clean(
      info?.querySelector('.kmlevs')?.text ??
          RegExp(r'Lv\.\s*\d+').firstMatch(bodyText)?.group(0) ??
          '',
    );

    return UserProfile(
      uid: resolvedUid,
      username: name,
      avatar: avatar,
      level: level,
      credits: counts['金币'] ?? counts['积分'] ?? '',
      posts: counts['帖子'] ?? counts['主题'] ?? '',
      replies: counts['回复'] ?? '',
      followers: counts['粉丝'] ?? '',
      regTime: _parseRegTime(doc, bodyText),
      group: _clean(info?.querySelector('.kmlev:not(.kmlevs)')?.text ?? doc.querySelector('.comiis_space_group')?.text ?? ''),
    );
  }

  /// 注册时间。comiis 移动模板把值放在前面、标签放在后面：
  /// `<li><div class="profile_rs">2022-7-7 13:22</div><span>注册时间</span></li>`，
  /// 若按整页文本取「注册时间」后面的日期，会误取到下一条「最后访问」的时间。
  String _parseRegTime(Document doc, String bodyText) {
    final datePattern = RegExp(
      r'[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}(?:\s+[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?)?',
    );
    String extract(String text) => datePattern.firstMatch(text)?.group(0) ?? '';
    bool isLabel(String text) {
      final normalized = _clean(text).replaceAll(RegExp(r'[:：\s]'), '');
      return normalized == '注册时间' || normalized == '注册于' || normalized == '注册日期';
    }

    // comiis 移动模板 / 桌面 #pbbs：值在前或在同一行。
    for (final li in doc.querySelectorAll('li')) {
      final labelEl = li.querySelector('span, em, dt, strong');
      if (labelEl == null || !isLabel(labelEl.text)) continue;
      final value = extract(li.text.replaceFirst(labelEl.text, ''));
      if (value.isNotEmpty) return value;
    }

    // 默认移动模板的表格：<tr><td>注册时间: </td><td>值</td></tr>。
    for (final tr in doc.querySelectorAll('tr')) {
      final cells = tr.querySelectorAll('td, th');
      if (cells.isEmpty || !isLabel(cells.first.text)) continue;
      final value = extract(cells.length > 1 ? cells[1].text : cells.first.text);
      if (value.isNotEmpty) return value;
    }

    // 兜底：标签前后的日期，优先「值 + 标签」的写法（comiis 的排列顺序）。
    for (final candidate in [
      '${datePattern.pattern}\\s*(?:注册时间|注册于|注册日期)',
      '(?:注册时间|注册于|注册日期)\\s*[:：]?\\s*${datePattern.pattern}',
    ]) {
      final match = RegExp(candidate).firstMatch(bodyText);
      if (match == null) continue;
      final value = datePattern.firstMatch(match.group(0) ?? '')?.group(0) ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// 头像地址是否属于指定 uid（静态头像路径或 avatar.php?uid=）。
  bool _avatarMatchesUid(String url, int uid) {
    if (url.isEmpty || _isPlaceholderImage(url)) return false;
    final padded = uid.toString().padLeft(9, '0');
    final path = '${padded.substring(0, 3)}/${padded.substring(3, 5)}/${padded.substring(5, 7)}/${padded.substring(7, 9)}_avatar';
    return url.contains(path) || url.contains('uid=$uid');
  }

  /// 小黑屋（forum.php?mod=misc&action=showdarkroom，桌面模板表格）。
  /// 站点每页只给 11 条，底部「更多」按钮带 cid，需要顺着 cid 连续翻页才能取全。
  Future<List<DarkRoomEntry>> fetchDarkRoom() async {
    final entries = <DarkRoomEntry>[];
    final seen = <String>{};
    String? cid;
    for (var page = 0; page < 20; page++) {
      // 该页没有移动模板，移动 UA 会被引导页拦截，必须用桌面模板。
      final query = <String, String>{'mod': 'misc', 'action': 'showdarkroom'};
      if (cid != null) query['cid'] = cid;
      final result = await _getDesktopPage('forum.php', query);
      _ensureOk(result);
      final doc = parser.parse(result.body);
      final before = entries.length;
      for (final tr in doc.querySelectorAll('#darkroomtable tr')) {
        final cells = tr.querySelectorAll('td');
        if (cells.length < 4) continue;
        final link = cells[0].querySelector('a[href]');
        final href = link?.attributes['href'] ?? '';
        final uid = int.tryParse(
              RegExp(r'space-uid-(\d+)\.html').firstMatch(href)?.group(1) ??
                  RegExp(r'[?&]uid=(\d+)').firstMatch(href)?.group(1) ??
                  '',
            ) ??
            0;
        final name = _clean(link?.text ?? cells[0].text);
        if (name.isEmpty || !seen.add('$uid|$name')) continue;
        entries.add(DarkRoomEntry(
          uid: uid,
          name: name,
          action: _clean(cells[1].text),
          expiry: _clean(cells[2].text),
          time: _clean(cells[3].text),
        ));
      }
      final next = _clean(doc.querySelector('#darkroommore')?.attributes['cid'] ?? '');
      // 没有「更多」、cid 不再变化或本页没有新记录时结束。
      if (next.isEmpty || next == cid || entries.length == before) break;
      cid = next;
    }
    return entries;
  }

  /// 勋章中心：返回（勋章目录, 最近获得记录）。
  Future<(List<MedalItem>, List<MedalRecord>)> fetchMedals() async {
    final result = await _http.get('home.php', query: {'mod': 'medal', 'mobile': '2'});
    _ensureOk(result);
    final doc = parser.parse(result.body);

    final items = <MedalItem>[];
    final seen = <String>{};
    for (final block in doc.querySelectorAll('p.list02_limg')) {
      final img = block.querySelector('img');
      final name = _clean(img?.attributes['alt'] ?? '');
      if (name.isEmpty || !seen.add(name)) continue;
      final onclick = block.querySelector('a')?.attributes['onclick'] ?? '';
      final desc = _clean(
        RegExp(r"kmtxt[^>]*>(.*?)<").firstMatch(onclick)?.group(1) ?? '',
      );
      items.add(MedalItem(name: name, image: _absolute(img?.attributes['src']), desc: desc));
    }

    final records = <MedalRecord>[];
    for (final a in doc.querySelectorAll('.comiis_medal_box a.block')) {
      final href = a.attributes['href'] ?? '';
      final uid = int.tryParse(RegExp(r'uid=(\d+)').firstMatch(href)?.group(1) ?? '') ?? 0;
      if (uid <= 0) continue;
      final time = _clean(a.querySelector('p.tit font')?.text ?? '');
      final titleText = _clean(a.querySelector('p.tit')?.text ?? '');
      final name = _clean(titleText.replaceAll(time, ''));
      final medal = _clean(a.querySelector('p.txt')?.text ?? '').replaceFirst('获得', '');
      if (name.isEmpty) continue;
      records.add(MedalRecord(
        uid: uid,
        name: name,
        medal: medal,
        avatar: _absolute(a.querySelector('img')?.attributes['src']),
        time: time,
      ));
    }
    return (items, records);
  }

  /// 积分页：余额与总积分（桌面模板 `ul.creditl`）。
  Future<CreditSummary> fetchCredits() async {
    final result = await _getDesktopPage('home.php', {
      'mod': 'spacecp',
      'ac': 'credit',
    });
    _ensureOk(result);
    final doc = parser.parse(result.body);

    final items = <CreditItem>[];
    var total = '';
    var formula = '';
    for (final li in doc.querySelectorAll('ul.creditl li')) {
      final labelEl = li.querySelector('em');
      final label = _clean(labelEl?.text ?? '').replaceAll(RegExp(r'[:：]\s*$'), '');
      final formulaEl = li.querySelector('span.xg1');
      var value = _clean(li.text);
      if (labelEl != null) value = value.replaceFirst(_clean(labelEl.text), '');
      if (formulaEl != null) value = value.replaceFirst(_clean(formulaEl.text), '');
      value = _clean(value);
      if (label.isEmpty || value.isEmpty) continue;
      final classes = (li.attributes['class'] ?? '').split(RegExp(r'\s+'));
      // 总积分行是 `<li class="cl"><em>积分: </em>...`；若有转账积分则是 `class="xi1 cl"`。
      if (classes.contains('cl') && !classes.contains('xi1')) {
        total = value;
        formula = _clean(formulaEl?.text ?? '');
        continue;
      }
      items.add(CreditItem(
        name: label,
        value: value,
        highlight: classes.contains('xi1'),
      ));
    }
    return CreditSummary(items: items, total: total, formula: formula);
  }

  /// 积分交易记录（`ac=credit&op=log`，桌面模板 `table.dt` 四列）。
  Future<List<CreditLog>> fetchCreditLogs({int page = 1}) async {
    final result = await _getDesktopPage('home.php', {
      'mod': 'spacecp',
      'ac': 'credit',
      'op': 'log',
      'page': '$page',
    });
    _ensureOk(result);
    final doc = parser.parse(result.body);

    final items = <CreditLog>[];
    for (final tr in doc.querySelectorAll('table.dt tr')) {
      final cells = tr.querySelectorAll('td');
      if (cells.length < 4) continue;
      final values = cells.map((cell) => _clean(cell.text)).toList();
      if (values[0] == '操作' || values[0].isEmpty && values[1].isEmpty) continue;
      items.add(CreditLog(
        operation: values[0],
        change: values[1],
        detail: values[2],
        time: values[3],
      ));
    }
    return items;
  }

  /// 道具商店（`home.php?mod=magic&action=shop`）。
  Future<List<MagicItem>> fetchMagicShop({int page = 1, bool hot = false}) async {
    final result = await _getDesktopPage('home.php', {
      'mod': 'magic',
      'action': 'shop',
      if (hot) 'operation': 'hot',
      'page': '$page',
    });
    _ensureOk(result);
    final doc = parser.parse(result.body);

    final items = <MagicItem>[];
    for (final li in doc.querySelectorAll('ul.mgcl li')) {
      final imgEl = li.querySelector('.mg_img img') ?? li.querySelector('img');
      final name = _clean(li.querySelector('p strong')?.text ?? imgEl?.attributes['alt'] ?? '');
      if (name.isEmpty) continue;

      final buy = li.querySelector('a[href*="operation=buy"]');
      final give = li.querySelector('a[href*="operation=give"]');
      final actionHref = (buy ?? give)?.attributes['href'] ?? '';
      var mid = _magicQueryValue(actionHref, 'mid');
      if (mid.isEmpty) {
        final imgId = imgEl?.parent?.attributes['id'] ?? '';
        mid = imgId.startsWith('magic_') ? imgId.substring(6) : '';
      }

      var priceText = '';
      for (final p in li.querySelectorAll('p')) {
        if (p.querySelector('strong.xi1') != null) {
          priceText = _clean(p.text);
          break;
        }
      }
      if (priceText.isEmpty) {
        final paragraphs = li.querySelectorAll('p');
        if (paragraphs.length > 1) priceText = _clean(paragraphs[1].text);
      }

      items.add(MagicItem(
        mid: mid,
        name: name,
        image: _absolute(imgEl?.attributes['src']),
        description: _clean(li.querySelector('.tip_c')?.text ?? ''),
        priceText: priceText,
        price: _clean(li.querySelector('strong.xi1')?.text ?? ''),
        soldOut: buy == null,
        canGive: give != null,
        saleVolume: _clean(li.querySelector('em.xg1')?.text ?? ''),
      ));
    }
    return items;
  }

  /// 我的道具（`home.php?mod=magic&action=mybox`）。
  Future<MagicBox> fetchMagicBox({int page = 1}) async {
    final result = await _getDesktopPage('home.php', {
      'mod': 'magic',
      'action': 'mybox',
      'page': '$page',
    });
    _ensureOk(result);
    final doc = parser.parse(result.body);

    final items = <MyMagic>[];
    for (final li in doc.querySelectorAll('ul.mgcl li')) {
      final imgEl = li.querySelector('.mg_img img') ?? li.querySelector('img');
      final name = _clean(li.querySelector('p strong')?.text ?? imgEl?.attributes['alt'] ?? '');
      if (name.isEmpty) continue;

      final use = li.querySelector('a[href*="operation=use"]');
      final give = li.querySelector('a[href*="operation=give"]');
      final sell = li.querySelector('a[href*="operation=sell"]');
      final drop = li.querySelector('a[href*="operation=drop"]');
      final actionHref = (use ?? give ?? sell ?? drop)?.attributes['href'] ??
          li.querySelector('a[href*="magicid="]')?.attributes['href'] ??
          '';
      final id = _firstInt(RegExp(r'[?&](?:amp;)?magicid=(\d+)').firstMatch(actionHref)?.group(1));
      if (id == null || id <= 0) continue;

      final fonts = li.querySelectorAll('p font');
      final num = _firstInt(_clean(fonts.isNotEmpty ? fonts.first.text : '')) ?? 0;
      final weight = fonts.length > 1 ? _clean(fonts[1].text) : '';

      items.add(MyMagic(
        id: id,
        name: name,
        image: _absolute(imgEl?.attributes['src']),
        description: _clean(li.querySelector('.tip_c')?.text ?? ''),
        num: num,
        weight: weight,
        canUse: use != null,
        canGive: give != null,
        canSell: sell != null,
        canDrop: drop != null,
      ));
    }
    return MagicBox(
      capacity: _clean(doc.querySelector('p.tbmu')?.text ?? ''),
      items: items,
    );
  }

  /// 道具日志（`action=log&operation=uselog|buylog|givelog|receivelog`）。
  Future<List<MagicLogEntry>> fetchMagicLogs(String type, {int page = 1}) async {
    final operation = const {'uselog', 'buylog', 'givelog', 'receivelog'}.contains(type)
        ? type
        : 'uselog';
    final result = await _getDesktopPage('home.php', {
      'mod': 'magic',
      'action': 'log',
      'operation': operation,
      'page': '$page',
    });
    _ensureOk(result);
    final doc = parser.parse(result.body);

    final items = <MagicLogEntry>[];
    for (final tr in doc.querySelectorAll('table.dt tr')) {
      final cells = tr.querySelectorAll('td');
      if (cells.length < 3) continue;
      final values = cells.map((cell) => _clean(cell.text)).toList();
      if (values.first.isEmpty) continue;
      items.add(MagicLogEntry(
        title: values[0],
        time: values.length > 1 ? values[1] : '',
        detail: values.skip(2).where((value) => value.isNotEmpty).join(' · '),
      ));
    }
    return items;
  }

  /// 购买道具。`mid` 为商店里的道具 identifier。
  Future<String> buyMagic({required String mid, int num = 1}) async {
    if (mid.isEmpty) throw SiteException('该道具当前不可购买');
    final formhash = await _fetchMagicFormhash(action: 'shop', operation: 'buy', mid: mid);
    return _submitMagic(action: 'shop', form: {
      'formhash': formhash,
      'operation': 'buy',
      'mid': mid,
      'magicnum': '$num',
      'operatesubmit': 'yes',
    });
  }

  /// 购买后直接赠送给他人。
  Future<String> giftMagicFromShop({
    required String mid,
    required String username,
    int num = 1,
    String message = '',
  }) async {
    if (mid.isEmpty) throw SiteException('该道具当前不可赠送');
    final formhash = await _fetchMagicFormhash(action: 'shop', operation: 'give', mid: mid);
    return _submitMagic(action: 'shop', form: {
      'formhash': formhash,
      'operation': 'give',
      'mid': mid,
      'magicnum': '$num',
      'tousername': username,
      'givemessage': message,
      'operatesubmit': 'yes',
    });
  }

  /// 读取「使用道具」操作页的表单字段。
  Future<MagicUseForm> fetchMagicUseForm(int magicId) async {
    final page = await _getDesktopPage('home.php', {
      'mod': 'magic',
      'action': 'mybox',
      'operation': 'use',
      'magicid': '$magicId',
      'infloat': 'yes',
    });
    _ensureOk(page);
    final doc = parser.parse(page.body);
    final formhash = _findFormhash(page.body);
    if (formhash.isEmpty) {
      throw SiteException(_messageText(doc) ?? '该道具当前无法使用');
    }

    final form = doc.querySelector('form#magicform') ??
        doc.querySelector('form[action*="mod=magic"]');
    final parsed = form == null
        ? (hidden: <String, String>{}, fields: <MagicFormField>[])
        : _parseSiteForm(
            form,
            skipNames: const {'formhash', 'operation', 'magicid', 'usesubmit', 'handlekey'},
          );
    return MagicUseForm(formhash: formhash, hidden: parsed.hidden, fields: parsed.fields);
  }

  /// 识别站点表单：隐藏域作为提交参数，输入项作为原生表单字段。
  ({Map<String, String> hidden, List<MagicFormField> fields}) _parseSiteForm(
    Element form, {
    Set<String> skipNames = const <String>{},
  }) {
    final hidden = <String, String>{};
    final fields = <MagicFormField>[];
    final radios = <String>{};
    for (final input in form.querySelectorAll('input')) {
      final name = (input.attributes['name'] ?? '').trim();
      if (name.isEmpty) continue;
      final type = (input.attributes['type'] ?? 'text').toLowerCase();
      final value = input.attributes['value'] ?? '';
      if (type == 'hidden') {
        if (skipNames.contains(name)) continue;
        hidden[name] = value;
        continue;
      }
      if (skipNames.contains(name) ||
          type == 'submit' ||
          type == 'button' ||
          type == 'reset' ||
          type == 'image') {
        continue;
      }
      if (type == 'radio') {
        if (!radios.add(name)) continue;
        fields.add(MagicFormField(
          name: name,
          label: _magicFieldLabel(input),
          type: MagicFieldType.radio,
          value: value == '1' ? '1' : '0',
          options: const [MagicFieldOption('1', '是'), MagicFieldOption('0', '否')],
        ));
        continue;
      }
      if (type == 'checkbox') continue;
      fields.add(MagicFormField(
        name: name,
        label: _magicFieldLabel(input),
        value: value,
      ));
    }
    for (final select in form.querySelectorAll('select')) {
      final name = (select.attributes['name'] ?? '').trim();
      if (name.isEmpty || skipNames.contains(name)) continue;
      final options = <MagicFieldOption>[];
      var selected = '';
      for (final option in select.querySelectorAll('option')) {
        final value = (option.attributes['value'] ?? '').trim();
        if (value.isEmpty) continue;
        options.add(MagicFieldOption(value, _clean(option.text)));
        if (option.attributes.containsKey('selected')) selected = value;
      }
      if (options.isEmpty) continue;
      fields.add(MagicFormField(
        name: name,
        label: _magicFieldLabel(select),
        type: MagicFieldType.select,
        value: selected.isEmpty ? options.first.value : selected,
        options: options,
      ));
    }
    for (final area in form.querySelectorAll('textarea')) {
      final name = (area.attributes['name'] ?? '').trim();
      if (name.isEmpty || skipNames.contains(name)) continue;
      fields.add(MagicFormField(
        name: name,
        label: _magicFieldLabel(area),
        type: MagicFieldType.textarea,
        value: _clean(area.text),
      ));
    }
    return (hidden: hidden, fields: fields);
  }

  Future<String> useMagic({
    required int magicId,
    required MagicUseForm form,
    Map<String, String> values = const {},
  }) {
    return _submitMagic(action: 'mybox', form: {
      'formhash': form.formhash,
      'operation': 'use',
      'magicid': '$magicId',
      'usesubmit': 'yes',
      ...form.hidden,
      ...values,
    });
  }

  Future<String> giveMagic({
    required int magicId,
    required String username,
    int num = 1,
    String message = '',
  }) async {
    final formhash = await _fetchMagicFormhash(action: 'mybox', operation: 'give', magicId: magicId);
    return _submitMagic(action: 'mybox', form: {
      'formhash': formhash,
      'operation': 'give',
      'magicid': '$magicId',
      'tousername': username,
      'magicnum': '$num',
      'givemessage': message,
      'operatesubmit': 'yes',
    });
  }

  Future<String> sellMagic({required int magicId, int num = 1}) async {
    final formhash = await _fetchMagicFormhash(action: 'mybox', operation: 'sell', magicId: magicId);
    return _submitMagic(action: 'mybox', form: {
      'formhash': formhash,
      'operation': 'sell',
      'magicid': '$magicId',
      'magicnum': '$num',
      'operatesubmit': 'yes',
    });
  }

  Future<String> dropMagic({required int magicId, int num = 1}) async {
    final formhash = await _fetchMagicFormhash(action: 'mybox', operation: 'drop', magicId: magicId);
    return _submitMagic(action: 'mybox', form: {
      'formhash': formhash,
      'operation': 'drop',
      'magicid': '$magicId',
      'magicnum': '$num',
      'operatesubmit': 'yes',
    });
  }

  /// 读取道具操作页里的 formhash（操作页是站点唯一稳定输出该凭证的地方）。
  Future<String> _fetchMagicFormhash({
    required String action,
    required String operation,
    String? mid,
    int? magicId,
  }) async {
    final page = await _getDesktopPage('home.php', {
      'mod': 'magic',
      'action': action,
      'operation': operation,
      if (mid != null) 'mid': mid,
      if (magicId != null) 'magicid': '$magicId',
      'infloat': 'yes',
    });
    _ensureOk(page);
    final formhash = _findFormhash(page.body);
    if (formhash.isEmpty) {
      throw SiteException(_messageText(parser.parse(page.body)) ?? '该操作当前不可用');
    }
    return formhash;
  }

  Future<String> _submitMagic({required String action, required Map<String, String> form}) async {
    final result = await _http.post(
      'home.php',
      query: {'mod': 'magic', 'action': action, 'mobile': 'no'},
      form: form,
      referer: AppConfig.uri('home.php', {'mod': 'magic', 'action': action}).toString(),
      userAgent: _desktopUserAgent,
    );
    _http.removeCookie('mobile');
    _ensureOk(result);

    final doc = parser.parse(result.body);
    final box = doc.querySelector('#messagetext');
    final message = _messageText(doc);
    if (box != null) {
      final classes = box.attributes['class'] ?? '';
      if (classes.contains('alert_error') ||
          (message != null && _looksLikeError(message))) {
        throw SiteException(message ?? '操作失败，请稍后重试');
      }
    } else if (message != null && _looksLikeError(message)) {
      throw SiteException(message);
    }
    return message ?? '操作成功';
  }

  /// 桌面消息页的正文（`#messagetext` 的第一个段落）。
  String? _messageText(Document doc) {
    final box = doc.querySelector('#messagetext');
    if (box != null) {
      final text = _clean(box.querySelector('p')?.text ?? box.text);
      if (text.isNotEmpty) return text;
    }
    return _pageMessage(doc);
  }

  String _magicQueryValue(String href, String key) {
    final match = RegExp('[?&](?:amp;)?$key=([^&]+)').firstMatch(href);
    final value = match?.group(1) ?? '';
    if (value.isEmpty) return '';
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  /// 表单字段标签：优先取紧邻的提示段落，其次取表格行的表头。
  String _magicFieldLabel(Element element) {
    var previous = element.previousElementSibling;
    while (previous != null && previous.localName == 'script') {
      previous = previous.previousElementSibling;
    }
    final text = _clean(previous?.text ?? '');
    if (text.isNotEmpty && text.length <= 60) return text;
    final th = element.parent?.parent?.querySelector('th');
    final header = _clean(th?.text ?? '');
    return header.length <= 60 ? header : '';
  }

  /// 通用站点模块：返回（提示文案, 列表行）。
  Future<(String, List<SiteRow>)> fetchModule(String path, Map<String, String> query) async {
    final result = await _http.get(path, query: query);
    _ensureOk(result);
    final doc = parser.parse(result.body);

    final tip = _clean(
      doc.querySelector('.comiis_password_top p')?.text ??
          doc.querySelector('.alert_info')?.text ??
          doc.querySelector('.alert_error')?.text ??
          '',
    );

    final rows = <SiteRow>[];
    final seen = <String>{};
    for (final li in doc.querySelectorAll('.comiis_bodybox li, #ct li, .comiis_list01 li')) {
      final classes = li.attributes['class'] ?? '';
      if (classes.contains('comiis_left_Touch')) continue;
      final link = li.querySelector('a[href]');
      final href = _absolute(link?.attributes['href']);
      final text = _clean(li.text);
      if (text.isEmpty || text.length > 300) continue;
      final img = li.querySelector('img');
      final title = _clean(
        li.querySelector('.tit, .title, h3, h4, strong')?.text ?? link?.text ?? text,
      );
      if (title.isEmpty || !seen.add('$title|$href')) continue;
      var rest = _clean(text.replaceFirst(title, ''));
      // 插件列表的倒计时由页面脚本填充，静态 HTML 里只有 00 天占位，改用真实时间。
      final timeLabel = _mallTimeLabel(li.querySelector('span.time'));
      rest = _clean(rest.replaceFirst(RegExp(r'\d+\s*天\s*\d+\s*小时\s*\d+\s*分\s*\d+\s*秒'), ''));
      if (timeLabel.isNotEmpty) rest = rest.isEmpty ? timeLabel : '$timeLabel · $rest';
      rows.add(SiteRow(
        title: title,
        subtitle: rest,
        image: _absolute(img?.attributes['src']),
        href: href,
      ));
      if (rows.length >= 60) break;
    }
    return (tip, rows);
  }

  /// 积分商城商品详情（keke_integralmall 插件页）。
  Future<MallProduct> fetchMallProduct(int tid) async {
    final result = await _http.get(
      'keke_integralmall-view.html',
      query: {'tid': '$tid', 'mobile': '2'},
    );
    _ensureOk(result);
    final doc = parser.parse(result.body);

    String pick(String selector) => _clean(doc.querySelector(selector)?.text ?? '');

    final records = <SiteRow>[];
    final seen = <String>{};
    // 移动模板的兑换记录：div.dhlist li（时间 / 状态 / 用户名 / 金额）。
    for (final li in doc.querySelectorAll('.dhlist li')) {
      if ((li.attributes['class'] ?? '').contains('dhtitle')) continue;
      final name = _clean(li.querySelector('.dhname')?.text ?? '');
      if (name.isEmpty) continue;
      final time = _clean(li.querySelector('.ac')?.text ?? '');
      final amount = _clean(li.querySelector('.jyje')?.text ?? '');
      final meta = [time, amount].where((value) => value.isNotEmpty).join(' · ');
      if (!seen.add('$name|$meta')) continue;
      records.add(SiteRow(title: name, subtitle: meta));
      if (records.length >= 20) break;
    }
    if (records.isEmpty) {
      for (final tr in doc.querySelectorAll('.comiis_bodybox tr')) {
        final cells = tr.querySelectorAll('td');
        if (cells.length < 3) continue;
        final values = <String>[];
        for (final cell in cells) {
          final value = _clean(cell.text);
          if (value.isNotEmpty) values.add(value);
        }
        if (values.length < 3) continue;
        if (!seen.add(values.join('|'))) continue;
        records.add(SiteRow(title: values.first, subtitle: values.skip(1).join(' · ')));
        if (records.length >= 20) break;
      }
    }

    return MallProduct(
      tid: tid,
      title: _clean(
        doc.querySelector('.comiis_viewtit h2')?.text ??
            doc.querySelector('h2')?.text ??
            doc.querySelector('title')?.text ??
            '',
      ),
      image: _absolute(
        doc.querySelector('.mallitem img')?.attributes['src'] ??
            doc.querySelector('.item_l img')?.attributes['src'] ??
            doc.querySelector('.comiis_bodybox img')?.attributes['src'],
      ),
      price: pick('.price-real'),
      marketPrice: pick('.price-sell'),
      stock: pick('.count-take'),
      sold: pick('.count-rest'),
      startAt: _jsDate(result.body, 'stime'),
      endAt: _jsDate(result.body, 'etime'),
      views: pick('.item-assure b'),
      warning: pick('.item-warning'),
      buyHref: _absolute(doc.querySelector('a.buy-btn')?.attributes['href']),
      statusHref: _absolute(doc.querySelector('a.detail-btn')?.attributes['href']),
      records: records,
    );
  }

  /// 读取积分商城「立即抢购」确认页：返回站点要求的表单，或页面本身的结果文本。
  Future<MallCheckout> fetchMallCheckout(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null) throw SiteException('链接无效');
    final result = await _http.get(uri.path.replaceFirst('/', ''), query: uri.queryParameters);
    _ensureOk(result);
    final doc = parser.parse(result.body);

    if (doc.querySelector('form[action*="logging"]') != null || doc.querySelector('#loginform') != null) {
      throw SiteException('登录状态已失效，请重新登录');
    }

    final message = _pageMessage(doc);
    if (message != null && _looksLikeError(message)) throw SiteException(message);

    final container = doc.querySelector('.comiis_bodybox') ?? doc.querySelector('#ct') ?? doc.body;
    final preview = _visibleText(container, limit: 800);

    Element? form;
    for (final candidate in doc.querySelectorAll('form')) {
      final action = candidate.attributes['action'] ?? '';
      if (action.contains('logging') || action.contains('search')) continue;
      if (action.contains('keke_integralmall') ||
          candidate.querySelector('input[name="formhash"]') != null) {
        form = candidate;
        break;
      }
    }
    if (form == null) {
      return MallCheckout(preview: preview.isEmpty ? (message ?? '') : preview);
    }

    final rawAction = (form.attributes['action'] ?? '').trim();
    final action = rawAction.isEmpty ? href : _absolute(rawAction);
    final formhash = _findFormhash(result.body);
    final hasFormhashInput = form.querySelector('input[name="formhash"]') != null;
    if (formhash.isEmpty && !hasFormhashInput) {
      throw SiteException(message ?? '当前商品暂不可抢购');
    }

    final parsed = _parseSiteForm(form, skipNames: const {'formhash'});
    return MallCheckout(
      action: action,
      formhash: formhash,
      hidden: parsed.hidden,
      fields: parsed.fields,
      preview: preview,
    );
  }

  /// 提交积分商城下单表单，返回站点结果文本（成功提示 / 卡密等）。
  Future<String> submitMallCheckout(
    MallCheckout checkout, {
    Map<String, String> values = const {},
  }) async {
    final uri = Uri.tryParse(checkout.action);
    if (uri == null) throw SiteException('下单地址无效');
    final result = await _http.post(
      uri.path.replaceFirst('/', ''),
      query: uri.queryParameters,
      form: <String, String>{
        if (checkout.formhash.isNotEmpty) 'formhash': checkout.formhash,
        ...checkout.hidden,
        ...values,
      },
      referer: AppConfig.uri('plugin.php', {
        'id': 'keke_integralmall:keke_integralmall',
        'mobile': '2',
      }).toString(),
    );
    _ensureOk(result);
    final doc = parser.parse(result.body);
    final message = _pageMessage(doc);
    if (message != null && _looksLikeError(message)) throw SiteException(message);

    final container = doc.querySelector('.comiis_bodybox') ?? doc.querySelector('#ct') ?? doc.body;
    final text = _visibleText(container, limit: 800);
    if (text.isNotEmpty) return text;
    return message ?? '抢购成功';
  }

  /// 读取插件操作页的正文文本（例如查看卡密状态）。
  Future<String> fetchPluginText(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null) throw SiteException('链接无效');
    final result = await _http.get(uri.path.replaceFirst('/', ''), query: uri.queryParameters);
    _ensureOk(result);
    final doc = parser.parse(result.body);

    final container = doc.querySelector('.comiis_bodybox') ??
        doc.querySelector('#ct') ??
        doc.querySelector('.comiis_body') ??
        doc.body;

    // 表格型结果（订单 / 卡密列表）按行拼接，避免各列粘连。
    final rows = <String>[];
    for (final tr in (container?.querySelectorAll('tr') ?? const <Element>[])) {
      final values = tr
          .querySelectorAll('td, th')
          .map((cell) => _visibleText(cell, limit: 400))
          .where((value) => value.isNotEmpty)
          .toList();
      if (values.isEmpty) continue;
      final line = values.join(' · ');
      if (!rows.contains(line)) rows.add(line);
      if (rows.length >= 60) break;
    }

    var output = rows.isNotEmpty ? rows.join('\n') : _visibleText(container);
    if (output.isEmpty) output = _pageMessage(doc) ?? '';
    return output.length > 1200 ? '${output.substring(0, 1200)}…' : output;
  }

  /// 执行站点模块行上的原生操作（GET，例如领取勋章、购买道具）。
  Future<String> performModuleAction(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null) throw SiteException('链接无效');
    final result = await _http.get(
      uri.path.replaceFirst('/', ''),
      query: uri.queryParameters,
      referer: AppConfig.uri('home.php', {'mod': 'space', 'do': 'profile', 'mobile': '2'}).toString(),
    );
    _ensureOk(result);
    final message = _pageMessage(parser.parse(result.body));
    if (message != null && _looksLikeError(message)) throw SiteException(message);
    return message ?? '操作成功';
  }

  String decode(List<int> bytes) => WafSolver.decodeUtf8(bytes);
}
