import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/browse_history.dart';
import '../../services/offline_thread_cache.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../../core/native_bridge.dart';
import '../../core/reply_notice.dart';
import '../../core/thread_paging.dart';
import '../../data/forum_repository.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_controls.dart';
import '../widgets/glass_menu.dart';
import '../widgets/measure_height.dart';
import '../widgets/emoji_panel.dart';
import '../widgets/post_html_view.dart';
import '../widgets/reply_composer.dart';
import '../widgets/state_views.dart';
import '../widgets/user_avatar.dart';
import 'login_page.dart';
import 'pm_page.dart';
import 'user_page.dart';
import '../navigation/app_routes.dart';
import '../widgets/glass_dialog.dart';

/// 帖子详情：楼层流 + 分页加载 + 点赞 / 收藏 / 回复 / 楼中楼。
class ThreadPage extends StatefulWidget {
  const ThreadPage({super.key, required this.tid, this.title = '', this.initialPid = 0})
      : previewDetail = null,
        previewPosts = null;

  /// 测试专用构造：直接喂一份已经解析好的主题，跳过网络请求。
  ///
  /// 楼层卡片、点评、楼中楼全在 [_postCard] 里，没有数据就只能测到空态，
  /// 布局回归也就无从谈起。生产代码只走上面那个构造。
  @visibleForTesting
  ThreadPage.preview({
    super.key,
    required ThreadDetail detail,
    required List<ForumPost> posts,
  })  : tid = detail.tid,
        title = '',
        initialPid = 0,
        previewDetail = detail,
        previewPosts = posts;

  final int tid;
  final String title;

  /// 从楼层链接（`mod=redirect&goto=findpost`）进来时要定位的楼层。
  ///
  /// 服务端收到 pid 会直接返回该楼所在的那一页，所以只要把 pid 带进首次
  /// 请求就够了；没有 pid（从列表、搜索进来）时是 0。
  final int initialPid;
  final ThreadDetail? previewDetail;
  final List<ForumPost>? previewPosts;

  /// 评论区标题该不该出现：只在第一页、主题正文之后插一次。
  ///
  /// 第二页起整页都是回复，再插标题会把它塞到本页第 1、2 楼之间。
  @visibleForTesting
  static bool needsSectionHeader({
    required int page,
    required bool onlyOp,
    required int postCount,
    required bool firstPostIsOp,
  }) =>
      !onlyOp && page == 1 && postCount >= 2 && firstPostIsOp;

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<ThreadPage> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocus = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final List<int> _replyAttachments = <int>[];

  ThreadDetail? _detail;
  final List<ForumPost> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  bool _uploading = false;
  bool _favorited = false;
  bool _liked = false;
  bool _disliked = false;
  bool _showEmoji = false;
  bool _onlyOp = false;
  bool _orderDesc = false;
  bool _voting = false;
  final Set<int> _pollSelected = <int>{};
  ForumPost? _replyTarget;
  int _likes = 0;
  int _dislikes = 0;
  String? _error;
  int _page = 1;
  bool _hasMore = false;

  /// 楼层定位只做一次：之后「只看楼主」重载不该把用户再拽回那一楼。
  bool _initialPidHandled = false;

  /// 当前这一页里已经显示过的楼层 pid，用来识别「站点把最后一页又发了一遍」。
  final Set<int> _shownPids = <int>{};

  /// 第 1 页顶部展示过的置顶回复 pid。
  ///
  /// 站点只在第 1 页插入一份置顶，它原本所在的页仍会返回同一条，
  /// 翻到那一页时按 pid 跳过，避免同一楼出现两次。
  Set<int> _pinnedPids = <int>{};

  /// 楼层定位用的 key：回复成功后滚到自己那条。
  final Map<int, GlobalKey> _floorKeys = <int, GlobalKey>{};

  ForumRepository get _repo => AppState.instance.repo;

  @override
  void initState() {
    super.initState();
    final preview = widget.previewDetail;
    if (preview != null) {
      _detail = preview;
      _posts.addAll(widget.previewPosts ?? preview.posts);
      _loading = false;
      _hasMore = preview.hasMore;
      _likes = preview.likes;
      _dislikes = preview.dislikes;
      _liked = preview.liked || AppState.instance.isThreadLiked(widget.tid);
      _favorited = preview.favorited;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _replyController.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  String get _link => AppConfig.uri('thread-${widget.tid}-1-1.html').toString();

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final detail = await _repo.fetchThread(
        widget.tid,
        // 带 pid 时服务端会 302 到该楼所在页，page 参数让位给 pid。
        pid: widget.initialPid > 0 ? widget.initialPid : null,
        authorId: _onlyOp ? _opUid : null,
        orderDesc: _orderDesc,
      );
      if (!mounted) return;
      _pinnedPids = ThreadPaging.pinnedPidsOf(detail.posts);
      setState(() {
        _detail = detail;
        _posts
          ..clear()
          ..addAll(ThreadPaging.withoutPinnedDuplicates(detail.posts, _pinnedPids));
        // 按 pid 进来时这一份其实是第 N 页，翻页要从 N 继续。
        _page = detail.page;
        _hasMore = detail.hasMore;
        _likes = detail.likes;
        _dislikes = detail.dislikes;
        // 页面解析是主来源；解析不出（模板没有状态类名）时保留本地已知状态，
        // 再用本机记录兜底——只靠页面的话，每次重进都会变回未赞。
        _liked = detail.liked || _liked || AppState.instance.isThreadLiked(widget.tid);
        _favorited = detail.favorited;
        _pollSelected.clear();
        _loading = false;
      });
      _recordHistory(detail);
      _locateInitialPid(detail);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _message(e);
        _loading = false;
      });
    }
  }

  int get _opUid {
    final uid = _detail?.uid ?? 0;
    if (uid > 0) return uid;
    return _posts.isNotEmpty ? _posts.first.uid : 0;
  }

  /// 从楼层链接进来时滚到目标楼。
  ///
  /// 列表是懒构建的：目标楼不在首屏时根本拿不到它的 context，这时就停在
  /// 页顶，只提示一句「已定位到第 N 页」——至少翻页起点是对的。
  Future<void> _locateInitialPid(ThreadDetail detail) async {
    final pid = widget.initialPid;
    if (_initialPidHandled || pid <= 0) return;
    _initialPidHandled = true;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final target = _floorKeys[pid]?.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        alignment: 0.1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
      return;
    }
    if (detail.page > 1) _toast('已定位到第 ${detail.page} 页');
  }

  Future<void> _setOnlyOp(bool value) async {
    setState(() {
      _onlyOp = value;
      _showEmoji = false;
    });
    await _load();
  }

  Future<void> _setOrderDesc(bool value) async {
    setState(() {
      _orderDesc = value;
      _showEmoji = false;
    });
    await _load();
  }

  Future<void> _loadMore() => _loadPage(_page + 1);

  Future<void> _loadPrevious() => _loadPage(_page - 1);

  /// 刷新当前页但不把用户甩回第一页顶部；回复、编辑、删除和下拉刷新都用它。
  Future<void> _refreshKeepPosition({bool quiet = false}) async {
    final page = _page;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    // 统一走分页加载：page 1 也用它，避免 _load() 把整页切换成骨架屏而丢掉位置。
    await _loadPage(page, jumpToTop: false, quiet: quiet);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scroll.hasClients) return;
    _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  /// 滚动到指定楼层；楼层还没构建时退化为滚到底部。
  Future<void> _scrollToPost(int pid) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scroll.hasClients) return;
    final target = _floorKeys[pid]?.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        alignment: 0.12,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
      return;
    }
    await _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  /// 显式分页：每页显示站点返回的 10 条楼层，切页时替换当前列表，
  /// 不再滚动到底自动追加，避免不同页的楼层和评论混在一起。
  Future<void> _loadPage(int page, {bool jumpToTop = true, bool quiet = false}) async {
    if (_loadingMore || page < 1 || (page > _page && !_hasMore)) return;
    setState(() => _loadingMore = true);
    try {
      final detail = await _repo.fetchThread(
        widget.tid,
        page: page,
        authorId: _onlyOp ? _opUid : null,
        orderDesc: _orderDesc,
      );
      if (!mounted) return;
      final offset = _orderDesc ? 0 : (page - 1) * AppConfig.postsPerPage;
      // 站点的 page 超过总页数时不会报错，直接把最后一页再发一遍。
      // 分页链接一旦解析偏了，这里就会拿到和上一页一模一样的楼：
      // 页码跳到 2、内容纹丝不动，点多少次都到不了底。按 pid 认重，
      // 认出来就停在当前页并收掉「下一页」。
      // 只在往下一页翻时判重：刷新当前页（编辑、删除后用）楼号集合本来就
      // 一样，判重会把刚保存的新正文丢掉，看起来就像「改完没生效」。
      if (page > _page && ThreadPaging.isRepeatedPage(_shownPids, detail.posts)) {
        setState(() {
          _loadingMore = false;
          _hasMore = false;
        });
        if (!quiet) _toast('已经到底了');
        return;
      }
      // 第 1 页顶部那条置顶只是站点的额外副本，它原本所在的页
      // 还会照常返回同一楼。先记下 pid，后面翻到那页时跳掉。
      if (page == 1) _pinnedPids = ThreadPaging.pinnedPidsOf(detail.posts);
      final visible = ThreadPaging.withoutPinnedDuplicates(detail.posts, _pinnedPids);
      setState(() {
        _shownPids
          ..clear()
          ..addAll(detail.posts.map((post) => post.pid));
        _page = page;
        _posts
          ..clear()
          ..addAll(visible.map((post) => post.copyWith(
            floor: post.isPinned ? post.floor : post.floor + offset,
          )));
        _hasMore = detail.hasMore;
        _loadingMore = false;
      });
      if (page == 1) _recordHistory(detail);
      if (jumpToTop && _scroll.hasClients) {
        await _scroll.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      if (!quiet) _toast(_message(e));
    }
  }

  String _message(Object error) => error is SiteException ? error.message : '加载失败，请稍后重试';

  /// 记一条浏览历史。只在第一页成功加载后调用，翻页/刷新不重复写。
  void _recordHistory(ThreadDetail detail) {
    if (detail.tid <= 0) return;
    final first = detail.posts.isEmpty ? null : detail.posts.first;
    final cover = first?.images.firstWhere(
          (value) => value.trim().isNotEmpty,
          orElse: () => '',
        ) ??
        '';
    BrowseHistory.instance.record(
      tid: detail.tid,
      title: detail.title.isEmpty ? widget.title : detail.title,
      boardName: detail.boardName,
      author: detail.author,
      cover: cover,
      postedAt: detail.time,
      replies: detail.replies,
      views: detail.views,
    );
  }

  Future<bool> _ensureLogin() async {
    if (AppState.instance.isLoggedIn) return true;
    final ok = await Navigator.of(context).push<bool>(
      noSwipeRoute(builder: (_) => const LoginPage()),
    );
    return ok == true && AppState.instance.isLoggedIn;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------- 回复 / 楼中楼

  void _focusReply() {
    setState(() => _replyTarget = null);
    _replyFocus.requestFocus();
  }

  /// 回复某楼：提交时带上服务端算好的 `repquote` 引用条，发出来和网页端
  /// 点「回复」的结果一致——正文顶部有一段灰色引用框，写着谁在哪层说的。
  /// 引用条只走 `noticetrimstr` 隐藏域，不写进正文，否则服务端会再插一份，
  /// 网页端就会出现两段一模一样的引用（见 [buildReplyNotice] 的说明）。
  void _startReply(ForumPost post) {
    setState(() {
      _replyTarget = post;
      _showEmoji = false;
    });
    _replyFocus.requestFocus();
  }

  void _clearReplyTarget() {
    setState(() => _replyTarget = null);
  }

  Future<void> _sendReply() async {
    final visibleText = _replyController.text.trim();
    final target = _replyTarget;
    if (visibleText.isEmpty && _replyAttachments.isEmpty) {
      _toast('请输入回复内容');
      return;
    }
    if (!await _ensureLogin()) return;
    final detail = _detail;
    if (detail == null || detail.formhash.isEmpty) {
      _toast('回复信息已失效，请下拉刷新后重试');
      return;
    }
    if (detail.fid == 0) {
      _toast('无法识别帖子所属版块');
      return;
    }
    if (!mounted) return;
    setState(() => _sending = true);
    try {
      // 回复某一楼：先到回复页取服务端算好的引用条（noticeauthor / noticetrimstr）。
      // 带上它，网页端看到的才是「回复某某的帖子」那种引用框，而不是一条独立回复。
      var noticeAuthor = '';
      var noticeTrim = '';
      var noticeAuthorMsg = '';
      if (target != null) {
        final ctx = await _repo.fetchReplyContext(
          tid: widget.tid,
          fid: detail.fid,
          pid: target.pid,
        );
        noticeAuthor = ctx.noticeAuthor;
        noticeAuthorMsg = ctx.noticeAuthorMsg;
        // 正文只放用户打的字，引用条单独交给 noticetrimstr；
        // 两边都带的话服务端会前插一次，引用就重复了。
        noticeTrim = ctx.noticeTrim.isNotEmpty
            ? ctx.noticeTrim
            : buildReplyNotice(
                author: target.author,
                time: target.time,
                pid: target.pid,
                tid: widget.tid,
              );
      }
      if (!mounted) return;
      final result = await _repo.reply(
        tid: widget.tid,
        fid: detail.fid,
        formhash: detail.formhash,
        message: visibleText,
        replyToPid: target?.pid,
        noticeAuthor: noticeAuthor,
        noticeTrim: noticeTrim,
        noticeAuthorMsg: noticeAuthorMsg,
        attachmentIds: List<int>.from(_replyAttachments),
      );
      if (!mounted) return;
      _replyController.clear();
      _replyAttachments.clear();
      _replyFocus.unfocus();
      setState(() {
        _replyTarget = null;
        _showEmoji = false;
      });
      final beforePids = _posts.map((post) => post.pid).toSet();
      _toast(result);
      // 刷新当前页而不是整篇重载：回复后要留在原处，并尽量滚到自己那条。
      await _refreshKeepPosition();
      if (!mounted) return;
      final added = _posts.where((post) => !beforePids.contains(post.pid)).toList();
      if (added.isNotEmpty) {
        await _scrollToPost(added.last.pid);
      }
    } catch (e) {
      _toast(_message(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attachReplyImage() async {
    final detail = _detail;
    if (detail == null) return;
    if (!await _ensureLogin()) return;
    // 帖子页自己不一定带上传凭证（手机模板的回复框经常没有上传按钮），
    // 缺了就去发帖页现取一份，这也顺带把 uid 拿到手。
    var uploadHash = detail.uploadHash;
    var uid = detail.uid;
    var reason = '帖子页里没有凭证';
    if (uploadHash.isEmpty || uid <= 0) {
      try {
        final info = await _repo.fetchComposeInfo(detail.fid);
        uploadHash = info.uploadHash;
        uid = info.uid;
        reason = info.debug;
      } catch (e) {
        reason = '发帖页打不开：${_message(e)}';
      }
    }
    if (uploadHash.isEmpty || uid <= 0) {
      _toast('没取到上传凭证（$reason）');
      return;
    }
    final picked = await _picker.pickMultiImage(maxWidth: 1600, imageQuality: 78);
    if (picked.isEmpty) return;
    if (!mounted) return;
    for (final file in picked) {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _uploading = true);
      try {
        final aid = await _repo.uploadAttachment(
          bytes: bytes,
          filename: file.name,
          uploadHash: uploadHash,
          uid: uid,
          fid: detail.fid,
          referer: _link,
        );
        if (!mounted) return;
        _replyAttachments.add(aid);
        insertAtCursor(_replyController, '\n[attachimg]$aid[/attachimg]\n');
        _toast('图片已插入回复');
      } catch (e) {
        _toast(_message(e));
      } finally {
        if (mounted) setState(() => _uploading = false);
      }
    }
  }

  void _toggleEmoji() {
    if (_showEmoji) {
      setState(() => _showEmoji = false);
      _replyFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _showEmoji = true);
  }

  // ------------------------------------------------------------- 点赞 / 收藏

  /// 更新点赞状态与计数，并把结果记到本机。
  ///
  /// 计数是乐观更新；状态必须落盘，否则退出重进又变回未赞，用户点一下只会
  /// 再收到一句「已经赞过」。
  void _applyLiked(bool liked) {
    final before = _liked;
    setState(() {
      _liked = liked;
      if (before != liked) {
        _likes = (_likes + (liked ? 1 : -1)).clamp(0, 1 << 31);
      }
    });
    AppState.instance.markThreadLiked(widget.tid, liked);
  }

  Future<void> _toggleLike() async {
    final detail = _detail;
    if (detail == null) return;
    if (!await _ensureLogin()) return;
    final wasLiked = _liked;
    try {
      await _repo.recommend(
        tid: widget.tid,
        formhash: detail.formhash,
        up: true,
        cancel: wasLiked,
        cancelHref: detail.likeHref,
      );
      if (!mounted) return;
      _applyLiked(!wasLiked);
      _toast(wasLiked ? '已取消点赞' : '点赞成功');
    } catch (e) {
      final message = _message(e);
      if (mounted && !wasLiked && message.contains('已经赞过')) {
        // 本地以为没赞、服务端说赞过：状态过期了。这一下用户点的是空心图标，
        // 想要的是「赞」，那就如实把图标点亮——以前读不到服务端状态，只能把
        // 这一下当成「其实你想取消」代劳，现在 [ThreadDetail.liked] 能读准，
        // 不需要再替用户做决定。真要取消，再点一次就走取消分支。
        setState(() => _liked = true);
        AppState.instance.markThreadLiked(widget.tid, true);
        _toast('这条你已经赞过了');
        return;
      }
      if (mounted && wasLiked && message.contains('已经赞过')) {
        // 取消请求没被站点接受，回的还是「已赞」。保持实心图标，别让用户
        // 以为取消成功了、重进又亮起来。
        setState(() => _liked = true);
        AppState.instance.markThreadLiked(widget.tid, true);
        _toast('站点未接受取消请求，当前仍是已赞');
        return;
      }
      if (mounted && message.contains('还没有点赞')) {
        // 反过来：服务端没有这条评价，本地却记着已赞，同样要把状态拉回来。
        setState(() => _liked = false);
        AppState.instance.markThreadLiked(widget.tid, false);
        _toast('你还没有点赞');
        return;
      }
      _toast(message);
    }
  }

  Future<void> _toggleDislike() async {
    final detail = _detail;
    if (detail == null) return;
    if (!await _ensureLogin()) return;
    try {
      await _repo.recommend(tid: widget.tid, formhash: detail.formhash, up: false);
      if (!mounted) return;
      setState(() {
        if (!_disliked) _dislikes += 1;
        _disliked = true;
      });
      _toast('已踩');
    } catch (e) {
      _toast(_message(e));
    }
  }

  Future<void> _toggleFavorite() async {
    if (!await _ensureLogin()) return;
    final detail = _detail;
    if (detail == null || detail.formhash.isEmpty) {
      _toast('收藏信息已失效，请下拉刷新后重试');
      return;
    }
    try {
      final wasFavorited = _favorited;
      final message = await _repo.toggleFavorite(
        tid: widget.tid,
        formhash: detail.formhash,
        favorited: wasFavorited,
        href: wasFavorited ? detail.favoriteHref : '',
      );
      if (!mounted) return;
      setState(() => _favorited = !wasFavorited);
      _toast(message);
    } catch (e) {
      _toast(_message(e));
    }
  }

  Future<void> _share() async {
    final title = widget.title.isEmpty ? _detail?.title ?? '帖子' : widget.title;
    final text = '$title\n$_link';
    final shared = await NativeBridge.shareText(text);
    if (shared) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toast('帖子链接已复制');
  }

  Future<void> _ratePost(ForumPost post) async {
    if (!await _ensureLogin()) return;
    if (_isMine(post)) {
      _toast('不能打赏自己的帖子');
      return;
    }
    final detail = _detail;
    if (detail == null || detail.formhash.isEmpty) {
      _toast('打赏信息已失效，请刷新后重试');
      return;
    }
    var options = RateOptions.fallback;
    try {
      options = await _repo.fetchRateOptions(tid: widget.tid, pid: post.pid);
    } catch (_) {
      // 读取失败时按好评 / 金币的常见范围兜底。
    }
    if (!mounted) return;
    if (options.notice.isNotEmpty) {
      _toast(options.notice);
      return;
    }
    if (options.fields.every((field) => field.ceiling <= 0)) {
      _toast('24 小时内可用的打赏额度已用完，请明天再试');
      return;
    }
    final result = await showModalBottomSheet<_RateResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RateSheet(
        floor: post.floorLabel,
        isOp: post.isOp,
        author: post.author,
        avatar: post.avatar,
        options: options,
      ),
    );
    if (result == null || !mounted) return;
    try {
      final message = await _repo.rate(
        tid: widget.tid,
        pid: post.pid,
        formhash: detail.formhash,
        scores: result.scores,
        reason: result.reason,
        notify: result.notify,
      );
      if (!mounted) return;
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_message(e));
    }
  }

  /// 踢帖：站点插件达到 5 票会自动送审核，需二次确认。
  Future<void> _kickThread() async {
    if (!await _ensureLogin()) return;
    final detail = _detail;
    if (detail == null || detail.kickToken.isEmpty) {
      _toast('当前页面没有踢帖入口');
      return;
    }
    if (!mounted) return;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: Text('踢帖（${detail.kickVotes}/${detail.kickLimit}）'),
        content: Text('踢帖满 ${detail.kickLimit} 人后主题进入审核，恶意踢帖可能被处罚。确定踢「${detail.title}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('确定踢帖')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final message = await _repo.kickThread(
        tid: widget.tid,
        token: detail.kickToken,
        formhash: detail.formhash,
      );
      if (!mounted) return;
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_message(e));
    }
  }

  Future<void> _moderate(String action, String label) async {
    if (!await _ensureLogin()) return;
    final detail = _detail;
    if (detail == null || detail.formhash.isEmpty) {
      _toast('操作信息已失效，请刷新后重试');
      return;
    }
    if (!mounted) return;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: Text('$label主题'),
        content: Text('确定要对「${detail.title}」执行$label操作吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final message = await _repo.moderate(
        tid: widget.tid,
        fid: detail.fid,
        formhash: detail.formhash,
        action: action,
      );
      if (!mounted) return;
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_message(e));
    }
  }

  /// 主题作者可以尝试置顶自己在本主题中的回复；最终权限仍由论坛服务端校验。
  Future<void> _toggleStickReply(ForumPost post) async {
    if (post.isOp) return;
    if (!_isThreadOwner && !_isModerator) {
      _toast('只有主题作者或版主可以置顶回复');
      return;
    }
    if (!await _ensureLogin()) return;
    final detail = _detail;
    if (detail == null || detail.formhash.isEmpty) {
      _toast('置顶信息已失效，请刷新后重试');
      return;
    }
    final stick = !post.isPinned;
    if (!mounted) return;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: Text(stick ? '置顶回复' : '取消置顶'),
        content: Text(stick
            ? '把第 ${post.floor} 楼置顶到主题正文下方？'
            : '取消第 ${post.floor} 楼的置顶？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(stick ? '置顶' : '取消置顶'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final message = await _repo.setStickReply(
        fid: detail.fid,
        tid: widget.tid,
        pid: post.pid,
        formhash: detail.formhash,
        stick: stick,
      );
      if (!mounted) return;
      _toast(message);
      // 置顶会改变楼层顺序，回到第一页才能看到结果。
      await _loadPage(1);
    } catch (e) {
      _toast(_message(e));
    }
  }

  Future<void> _openPm(ForumPost post) async {
    if (!await _ensureLogin()) return;
    if (!mounted) return;
    await Navigator.of(context).push(appRoute(
      builder: (_) => PmPage(uid: post.uid, name: post.author),
    ));
  }

  Future<void> _openInBrowser() async {
    await launchUrl(Uri.parse(_link), mode: LaunchMode.externalApplication);
  }

  void _copyFloor(ForumPost post) {
    // 带上 ptid：落地页自己也知道属于哪个主题，在 App 里点开能直接进原生
    // 帖子页，不用再为「这条楼号属于谁」多发一次请求。
    final url = AppConfig.uri('forum.php', {
      'mod': 'redirect',
      'goto': 'findpost',
      'ptid': '${widget.tid}',
      'pid': '${post.pid}',
    }).toString();
    Clipboard.setData(ClipboardData(text: url));
    _toast('楼层链接已复制');
  }

  bool _isMine(ForumPost post) {
    final uid = AppState.instance.profile?.uid ?? 0;
    return post.uid > 0 && uid > 0 && post.uid == uid;
  }

  /// 只有称号 / 等级为版主（或管理员）时才显示管理类菜单。
  bool get _isModerator {
    final profile = AppState.instance.profile;
    if (profile == null) return false;
    final title = '${profile.group} ${profile.level}';
    return title.contains('版主') || title.contains('管理员');
  }

  /// 当前登录用户是不是这个主题的作者。
  ///
  /// Discuz 允许主题作者置顶自己主题下的回复（`topicadmin_stickreply` 里的
  /// `$specialperm`），不需要版主权限，所以这里要按主题作者判断，
  /// 不能拿「本页第一条是不是我」来推断——翻到第 2 页时第一条是别人。
  bool get _isThreadOwner {
    final uid = AppState.instance.profile?.uid ?? 0;
    return uid > 0 && _opUid > 0 && uid == _opUid;
  }

  void _openUser(int uid, String name) {
    if (uid <= 0) return;
    Navigator.of(context).push(appRoute(builder: (_) => UserPage(uid: uid, name: name)));
  }

  Future<void> _handleFloorMenu(ForumPost post, String value) async {
    switch (value) {
      case 'copy':
        _copyFloor(post);
      case 'source':
        await _copySource(post);
      case 'report':
        await _report(post);
      case 'rate':
        await _ratePost(post);
      case 'pm':
        await _openPm(post);
      case 'edit':
        await _editPost(post);
      case 'delete':
        await _deletePost(post);
      case 'stick':
        await _toggleStickReply(post);
      case 'digest':
        await _moderate('digest', '精华');
      case 'close':
        await _moderate('close', '关闭');
      case 'warn':
        await _moderate('warn', '警告');
    }
  }

  /// 排错用：把这一楼的原始 HTML 放进剪贴板。
  /// 帖子里出现异常空白时，靠它确认到底是哪个标签占出来的。
  Future<void> _copySource(ForumPost post) async {
    await Clipboard.setData(ClipboardData(text: post.html));
    _toast('本楼源码已复制（${post.html.length} 字）');
  }

  Future<void> _report(ForumPost post) async {
    if (!await _ensureLogin()) return;
    final detail = _detail;
    if (detail == null) return;
    if (!mounted) return;
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ReportSheet(floor: post.floorLabel),
    );
    if (result == null || !mounted) return;
    try {
      final message = await _repo.report(
        fid: detail.fid,
        tid: widget.tid,
        pid: post.pid,
        formhash: detail.formhash,
        reason: result.$1,
        message: result.$2,
      );
      _toast(message);
    } catch (e) {
      _toast(_message(e));
    }
  }

  Future<void> _editPost(ForumPost post) async {
    final detail = _detail;
    if (detail == null) return;
    final result = await Navigator.of(context).push<Object?>(
      appRoute(
        builder: (_) => _EditPostPage(
          fid: detail.fid,
          tid: widget.tid,
          pid: post.pid,
          formhash: detail.formhash,
          // 回复没有标题，编辑页也不显示标题框；传空串让服务端留空，
          // 早先这里塞了 `Re: 主题`，结果楼层正文顶上多出一行重复标题。
          subject: post.isOp ? detail.title : '',
          message: _stripEditNotice(_plainText(post.html)),
          isOp: post.isOp,
        ),
      ),
    );
    if (result == true && mounted) {
      _toast('已保存修改');
      await _refreshKeepPosition();
    }
  }

  Future<void> _deletePost(ForumPost post) async {
    final detail = _detail;
    if (detail == null) return;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: const Text('删除确认'),
        content: Text('确定删除${post.isOp ? '整篇主题' : '第 ${post.floor} 楼的回复'}吗？删除后不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final message = await _repo.deletePost(
        fid: detail.fid,
        tid: widget.tid,
        pid: post.pid,
        formhash: detail.formhash,
        page: _page,
      );
      if (!mounted) return;
      if (post.isOp) {
        Navigator.of(context).maybePop();
        return;
      }
      // 服务端已经确认删掉了，本地直接跟着移除。刷新只为补齐删楼后的
      // 楼号位移，失败也不能把结论翻回「未生效」——早先按刷新结果判定，
      // 一次刷新出错就会对着已删除的楼层报错。
      _floorKeys.remove(post.pid);
      setState(() {
        _posts.removeWhere((item) => item.pid == post.pid);
        final current = _detail;
        if (current != null && current.replies > 0) {
          _detail = current.copyWith(replies: current.replies - 1);
        }
      });
      // 删掉的是本页最后一条时，当前页已经空了，退回上一页。
      if (_posts.isEmpty && _page > 1) {
        await _loadPage(_page - 1);
      } else {
        await _refreshKeepPosition(quiet: true);
      }
      if (!mounted) return;
      _toast(message);
    } catch (e) {
      _toast(_message(e));
    }
  }

  Future<void> _cacheForOffline() async {
    final current = _detail;
    if (current == null || _posts.isEmpty) {
      _toast('帖子内容尚未加载完成，暂时无法缓存');
      return;
    }
    _toast('正在缓存整篇帖子，评论和图片较多时可能需要一些时间');
    try {
      final first = await _repo.fetchThread(widget.tid, page: 1);
      // 置顶楼只在第 1 页额外插入，原页仍会返回它，缓存时同样要跳掉。
      final pinned = ThreadPaging.pinnedPidsOf(first.posts);
      final allPosts = <ForumPost>[
        ...ThreadPaging.withoutPinnedDuplicates(first.posts, pinned),
      ];
      var hasMore = first.hasMore;
      var page = 1;
      // Fetch every page, independently of the current "only OP" and sort filters.
      while (hasMore && page < 500) {
        page++;
        final next = await _repo.fetchThread(widget.tid, page: page);
        final offset = (page - 1) * AppConfig.postsPerPage;
        allPosts.addAll(ThreadPaging.withoutPinnedDuplicates(next.posts, pinned)
            .map((post) => post.copyWith(floor: post.isPinned ? post.floor : post.floor + offset)));
        hasMore = next.hasMore;
        if (next.posts.isEmpty && hasMore) break;
      }
      await OfflineThreadCache.instance.save(
        tid: widget.tid,
        title: first.title,
        boardName: first.boardName,
        author: first.author,
        time: first.time,
        views: first.views,
        replies: first.replies,
        posts: allPosts,
      );
      if (mounted) {
        final suffix = hasMore ? '（达到分页安全上限，已保存前 $page 页）' : '';
        _toast('已缓存整篇帖子：${allPosts.length} 条内容$suffix');
      }
    } catch (error) {
      if (mounted) _toast('缓存失败：${_message(error)}');
    }
  }

  void _handleMenu(String value) {
    switch (value) {
      case 'favorite':
        _toggleFavorite();
      case 'offlineCache':
        _cacheForOffline();
      case 'copy':
        _share();
      case 'browser':
        _openInBrowser();
      case 'refresh':
        _load();
      case 'onlyOp':
        _setOnlyOp(!_onlyOp);
      case 'order':
        _setOrderDesc(!_orderDesc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final title = detail?.title.isNotEmpty == true
        ? detail!.title
        : (widget.title.isEmpty ? '帖子详情' : widget.title);
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      // 输入框由页面自行避让键盘，避免被输入法遮挡。
      resizeToAvoidBottomInset: false,
      // 让正文从顶栏背后滚过，玻璃顶栏才有东西可模糊。
      extendBodyBehindAppBar: true,
      // 和其它页面共用同一套玻璃顶栏：透明底 + flexibleSpace 里的模糊底板 +
      // 底部发丝描边。之前这里为了描边和自定义 actions 又抄了一份。
      appBar: GlassAppBar(
        // 顶栏标题压到 16：正文里有一行 20.5 的大标题，两者挨着时默认的
        // 22sp 会和正文抢主次，看起来像标题被写了两遍。
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '分享链接',
            onPressed: _share,
            icon: const Icon(Icons.ios_share_rounded),
          ),
          GlassMenuButton<String>(
            tooltip: '更多',
            icon: Icons.more_vert_rounded,
            iconSize: 24,
            hitSize: 48,
            menuWidth: 224,
            dividers: true,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            items: _threadMenuItems(),
            onSelected: _handleMenu,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            // 列表铺满整个 body，正文和评论从回复框背后掠过，玻璃才透得出模糊。
            // 底部留白改在列表自己的 padding 里补：之前给这一层加 padding，
            // 等于把视口截短，框后面只剩 Scaffold 的纯色底，模糊纯色看不出一点玻璃感。
            Positioned.fill(child: _buildBody()),
            Positioned(
              left: 0,
              right: 0,
              bottom: insets,
              child: MeasureHeight(
                onHeight: _onComposerMeasured,
                child: _composer(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 回复框实测高度，首帧给个估值，量到真值后覆盖。
  ///
  /// 早先按「有回复目标 100、无目标 64、开表情 +220」估。估小了输入框
  /// 换行后最后一条回复被压在框下面，估大了尾部多一段空白，而且改一次
  /// 布局就要回来重算这几个数。现在回复框是悬浮胶囊，收起时 6 + 40 + 6 + 8。
  double _composerReserve = 60;

  /// 列表底部让给悬浮回复框的高度，键盘弹起时再加上键盘高度。
  ///
  /// 留白必须加在列表内容末尾，不能加在列表外层——外层留白会截短视口，
  /// 回复框背后就什么都透不出来了。胶囊自己已经带了 8 的外边距，这里再补
  /// 12，最后一条回复和胶囊之间才是一口气的距离。
  double get _composerBottomPadding =>
      _composerReserve + MediaQuery.viewInsetsOf(context).bottom + 12;

  void _onComposerMeasured(double height) {
    if ((height - _composerReserve).abs() < 0.5) return;
    setState(() => _composerReserve = height);
  }

  /// 正文区顶部要空出的高度：状态栏 + 顶栏。
  ///
  /// `extendBodyBehindAppBar` 之后 body 从屏幕最顶上开始，不补这一段，
  /// 标题会被顶栏盖住。
  double get _topInset => glassTopInset(context) + 8;

  /// 右上角菜单。
  List<GlassMenuItem<String>> _threadMenuItems() => [
        GlassMenuItem(
          value: 'favorite',
          icon: _favorited ? Icons.star_rounded : Icons.star_outline_rounded,
          label: _favorited ? '已收藏' : '收藏主题',
        ),
        const GlassMenuItem(
          value: 'offlineCache',
          icon: Icons.download_for_offline_outlined,
          label: '缓存帖子供离线阅读',
        ),
        const GlassMenuItem(value: 'copy', icon: Icons.link_rounded, label: '复制链接'),
        const GlassMenuItem(
          value: 'browser',
          icon: Icons.open_in_browser_rounded,
          label: '在浏览器打开',
        ),
        GlassMenuItem(
          value: 'onlyOp',
          icon: _onlyOp ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
          label: '只看楼主',
        ),
        GlassMenuItem(
          value: 'order',
          icon: _orderDesc ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
          label: '倒序浏览',
        ),
        const GlassMenuItem(value: 'refresh', icon: Icons.refresh_rounded, label: '刷新'),
      ];

  /// 评论区标题只属于第一页：它标记的是「主题正文结束、回复开始」。
  ///
  /// 早先只判断「列表第 2 项」，翻到第 2 页时本页第一楼恰好也是第 2 项，
  /// 于是标题被塞进 11 楼和 12 楼之间，看起来像两块不相干的内容。
  bool get _showsSectionHeader => ThreadPage.needsSectionHeader(
        page: _page,
        onlyOp: _onlyOp,
        postCount: _posts.length,
        firstPostIsOp: _posts.isNotEmpty && _posts.first.isOp,
      );

  Widget _buildBody() {
    if (_loading && _posts.isEmpty) {
      return const FeedSkeleton(count: 3);
    }
    if (_error != null && _posts.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshKeepPosition,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          children: [
            SizedBox(height: _topInset + 72),
            EmptyView(text: _detail?.notice.isNotEmpty == true ? _detail!.notice : '该帖子暂时没有可显示的内容'),
            SizedBox(height: _composerBottomPadding),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshKeepPosition,
      // 顶栏是玻璃、正文从它背后穿过，下拉圆圈要落到顶栏下面才看得见。
      edgeOffset: _topInset,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(kPageGutter, _topInset, kPageGutter, _composerBottomPadding),
        itemCount: 1 + _posts.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return _header();
          final postIndex = index - 1;
          if (postIndex < _posts.length) {
            final post = _posts[postIndex];
            if (postIndex == 1 && _showsSectionHeader) {
              final scheme = Theme.of(context).colorScheme;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 5, 4, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 9),
                        const Text('评论区', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        Text('${_detail?.replies ?? (_posts.length - 1)} 条回复',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                        const Spacer(),
                        Icon(Icons.forum_outlined, size: 17, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: _postCard(post),
                  ),
                ],
              );
            }
            return Padding(
              key: _floorKeys.putIfAbsent(post.pid, GlobalKey.new),
              padding: const EdgeInsets.only(bottom: 11),
              child: _postCard(post),
            );
          }
          return _footer();
        },
      ),
    );
  }

  Widget _header() {
    final detail = _detail;
    if (detail == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detail.title,
            style: const TextStyle(fontSize: 20.5, fontWeight: FontWeight.w800, height: 1.35),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (detail.boardName.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    detail.boardName,
                    style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w700),
                  ),
                ),
              _meta(Icons.person_outline_rounded, detail.author.isEmpty ? '未知作者' : detail.author),
              _meta(Icons.schedule_rounded, detail.time),
              _meta(Icons.chat_bubble_outline_rounded, '${detail.replies} 回复'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _actionButton(
                icon: _liked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
                label: _likes > 0 ? '赞 $_likes' : '赞',
                active: _liked,
                onTap: _toggleLike,
              ),
              _actionButton(
                icon: _disliked ? Icons.thumb_down_alt_rounded : Icons.thumb_down_alt_outlined,
                label: _dislikes > 0 ? '踩 $_dislikes' : '踩',
                active: _disliked,
                onTap: _toggleDislike,
              ),
              _actionButton(
                icon: _favorited ? Icons.star_rounded : Icons.star_outline_rounded,
                label: _favorited ? '已收藏' : '收藏',
                active: _favorited,
                onTap: _toggleFavorite,
              ),
              _actionButton(
                icon: Icons.ios_share_rounded,
                label: '分享',
                active: false,
                onTap: _share,
              ),
            ],
          ),
          if (detail.poll != null) ...[
            const SizedBox(height: 10),
            _pollCard(detail.poll!),
          ],
          const SizedBox(height: 6),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ],
      ),
    );
  }

  /// 投票卡片：显示选项与票数，未投票时可直接勾选提交。
  Widget _pollCard(Poll poll) {
    final scheme = Theme.of(context).colorScheme;
    final votable = !poll.expired && poll.options.every((option) => option.id > 0);
    final maxVotes = poll.options.fold<int>(1, (max, option) => option.votes > max ? option.votes : max);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.how_to_vote_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  poll.multiple ? '投票 · 多选' : '投票 · 单选',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary),
                ),
              ),
              Text(
                poll.total > 0 ? '${poll.total} 人参与' : (poll.expired ? '已结束' : '暂无投票'),
                style: TextStyle(fontSize: 10.5, color: scheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final option in poll.options)
            InkWell(
              onTap: votable && option.id > 0
                  ? () => setState(() {
                        if (poll.multiple) {
                          if (!_pollSelected.remove(option.id)) _pollSelected.add(option.id);
                        } else {
                          _pollSelected
                            ..clear()
                            ..add(option.id);
                        }
                      })
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      _pollSelected.contains(option.id)
                          ? (poll.multiple ? Icons.check_box_rounded : Icons.radio_button_checked_rounded)
                          : (poll.multiple ? Icons.check_box_outline_blank_rounded : Icons.radio_button_unchecked_rounded),
                      size: 17,
                      color: _pollSelected.contains(option.id) ? scheme.primary : scheme.outline,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(option.text, style: const TextStyle(fontSize: 12.5, height: 1.4)),
                          if (option.votes > 0) ...[
                            const SizedBox(height: 3),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: option.votes / (maxVotes == 0 ? 1 : maxVotes),
                                minHeight: 4,
                                backgroundColor: scheme.surfaceContainerHighest,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      option.votes > 0 ? '${option.votes} 票' : '',
                      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          if (votable && !poll.voted) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: _voting ? null : _vote,
                style: FilledButton.styleFrom(minimumSize: const Size(88, 32), padding: const EdgeInsets.symmetric(horizontal: 14)),
                child: _voting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('提交投票', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _vote() async {
    final detail = _detail;
    if (detail == null) return;
    if (!await _ensureLogin()) return;
    if (_pollSelected.isEmpty) {
      _toast('请先选择投票选项');
      return;
    }
    setState(() => _voting = true);
    try {
      final message = await _repo.votePoll(
        tid: widget.tid,
        fid: detail.fid,
        formhash: detail.formhash,
        ids: _pollSelected.toList(),
      );
      if (!mounted) return;
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_message(e));
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: active ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: scheme.outline),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _postCard(ForumPost post) {
    final scheme = Theme.of(context).colorScheme;
    final targeted = _replyTarget?.pid == post.pid;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      elevation: 0,
      color: post.isOp
          ? scheme.primary.withValues(alpha: 0.045)
          : scheme.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        // 主线楼层和回复用同一个圆角：之前主体 16、回复 12，一页里两种弧度
        // 挨在一起，看着像两套卡片。以 14 收齐。
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: targeted
              ? scheme.primary.withValues(alpha: 0.75)
              : post.isOp
                  ? scheme.primary.withValues(alpha: 0.38)
                  : scheme.outlineVariant.withValues(alpha: 0.55),
          width: targeted ? 1.5 : post.isOp ? 1.1 : 0.8,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, post.isOp ? 14 : 10, 14, post.isOp ? 10 : 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => _openUser(post.uid, post.author),
                  child: UserAvatar(url: post.avatar, name: post.author, size: 34),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: () => _openUser(post.uid, post.author),
                              child: Text(
                                post.author.isEmpty ? '匿名' : post.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          if (post.level.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: scheme.tertiary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                post.level,
                                style: TextStyle(fontSize: 9.5, color: scheme.tertiary, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [post.time, if (post.location.isNotEmpty) post.location].where((e) => e.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                // 网页端在作者行右侧标「置顶 来自2#」，这里同样给一枚置顶标记，
                // 楼层标签仍然按真实楼号显示。
                if (post.isPinned && !post.isOp) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5484D).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.push_pin, size: 11, color: Color(0xFFE5484D)),
                        SizedBox(width: 3),
                        Text(
                          '置顶',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE5484D),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: post.isOp
                        ? scheme.primary.withValues(alpha: 0.1)
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    post.isOp ? '主题正文' : post.seatLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: post.isOp ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            PostHtmlView(html: post.html, images: post.images, onReply: _focusReply),
            if (post.isOp && !_isMine(post)) ...[
              const SizedBox(height: 12),
              _opActions(post),
            ],
            if (post.rates.isNotEmpty || post.rateSummary.isNotEmpty) ...[
              const SizedBox(height: 10),
              _rateLog(post),
            ],
            if (post.comments.isNotEmpty) ...[
              const SizedBox(height: 10),
              _commentList(post),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                _floorAction(Icons.reply_rounded, '回复', () => _startReply(post), highlight: targeted),
                const Spacer(),
                GlassMenuButton<String>(
                  tooltip: '更多操作',
                  hitSize: 36,
                  menuWidth: 200,
                  items: _floorMenuItems(post),
                  onSelected: (value) => _handleFloorMenu(post, value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 楼层「更多」菜单的项。按身份和权限组合，和原来 PopupMenuItem 的顺序一致。
  List<GlassMenuItem<String>> _floorMenuItems(ForumPost post) => [
        const GlassMenuItem(value: 'copy', label: '复制楼层', icon: Icons.link_rounded),
        const GlassMenuItem(value: 'report', label: '举报', icon: Icons.flag_outlined),
        const GlassMenuItem(value: 'source', label: '复制本楼源码', icon: Icons.code_rounded),
        if (!_isMine(post))
          GlassMenuItem(
            value: 'rate',
            label: post.isOp ? '赞赏' : '打赏',
            icon: Icons.volunteer_activism_outlined,
          ),
        if (!_isMine(post) && post.uid > 0)
          const GlassMenuItem(value: 'pm', label: '发消息', icon: Icons.mail_outline_rounded),
        // 主题作者和版主都能置顶回复；已置顶的楼层给「取消置顶」。
        if (!post.isOp && (_isThreadOwner || _isModerator))
          GlassMenuItem(
            value: 'stick',
            label: post.isPinned ? '取消置顶' : '置顶回复',
            icon: post.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
          ),
        if (_isModerator) ...const [
          GlassMenuItem(value: 'digest', label: '设精华', icon: Icons.workspace_premium_outlined),
          GlassMenuItem(value: 'close', label: '关闭主题', icon: Icons.lock_outline_rounded),
          GlassMenuItem(value: 'warn', label: '警告', icon: Icons.gavel_rounded),
        ],
        if (_isMine(post)) ...const [
          GlassMenuItem(value: 'edit', label: '编辑', icon: Icons.edit_outlined),
          GlassMenuItem(value: 'delete', label: '删除', icon: Icons.delete_outline_rounded, danger: true),
        ],
      ];

  /// 楼主楼层底部的「赞赏 / 踢帖」按钮，与站点移动模板保持一致。
  Widget _opActions(ForumPost post) {
    final detail = _detail;
    final kickLabel = detail == null || detail.kickToken.isEmpty
        ? ''
        : '踢帖(${detail.kickVotes}/${detail.kickLimit})';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: () => _ratePost(post),
          icon: const Icon(Icons.volunteer_activism_outlined, size: 16),
          label: const Text('赞赏'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE3A008),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 9),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        if (kickLabel.isNotEmpty) ...[
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _kickThread,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            child: Text(kickLabel),
          ),
        ],
      ],
    );
  }

  /// 楼层打赏记录：`N 人参与了打赏` + 明细。
  Widget _rateLog(ForumPost post) {
    final scheme = Theme.of(context).colorScheme;
    final title = post.rateSummary.isNotEmpty ? post.rateSummary : '${post.rates.length} 人参与了打赏';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: scheme.tertiary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.volunteer_activism_outlined, size: 13, color: scheme.tertiary),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: scheme.tertiary),
              ),
            ],
          ),
          for (final record in post.rates.take(8))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(
                TextSpan(children: [
                  if (record.score.isNotEmpty)
                    TextSpan(
                      text: '${record.score} ',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: scheme.tertiary),
                    ),
                  TextSpan(
                    text: record.username.isEmpty ? '匿名' : record.username,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  if (record.reason.isNotEmpty)
                    TextSpan(
                      text: '：${record.reason}',
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _floorAction(IconData icon, String label, VoidCallback onTap, {required bool highlight}) {
    final scheme = Theme.of(context).colorScheme;
    final color = highlight ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11.5, color: color)),
          ],
        ),
      ),
    );
  }

  /// 回复某条点评：Discuz 的点评本身不是独立帖子，没有可用于 reppost 的 pid。
  /// 将点评内容引用到正式回复编辑器，并关联其所属楼层，避免 action=comment
  /// 将内容再次提交为普通点评。
  void _startCommentReply(ForumPost post, ForumComment comment) {
    final author = comment.author.isEmpty ? '匿名' : comment.author;
    final quotedText = comment.text.trim();
    final timeLabel = comment.time.isEmpty ? '' : ' 发表于 ${comment.time}';
    insertAtCursor(
      _replyController,
      '[quote][size=2][color=#999999]回复 $author$timeLabel[/color][/size]\n'
      '$quotedText\n[/quote]\n',
    );
    setState(() {
      _replyTarget = post;
      _showEmoji = false;
    });
    _replyFocus.requestFocus();
  }

  /// 楼中楼点评列表：点击任意一条可针对该条点评发起正式回复。
  Widget _commentList(ForumPost post) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      // 撑满卡片：Column 默认按内容宽度收缩，点评短的时候底板只有半截宽，
      // 同一个列表里每楼的底色宽窄不一。
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '楼中楼 · ${post.comments.length}',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: scheme.outline),
          ),
          const SizedBox(height: 4),
          for (final comment in post.comments)
            InkWell(
              onTap: () => _startCommentReply(post, comment),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: comment.author.isEmpty ? '匿名' : comment.author,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary),
                    ),
                    TextSpan(
                      text: comment.time.isEmpty ? '：' : '（${comment.time}）：',
                      style: TextStyle(fontSize: 10.5, color: scheme.outline),
                    ),
                    TextSpan(
                      text: comment.text,
                      style: TextStyle(fontSize: 12, height: 1.5, color: scheme.onSurface),
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    final scheme = Theme.of(context).colorScheme;
    final canGoPrevious = _page > 1 && !_loadingMore;
    final canGoNext = _hasMore && !_loadingMore;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 12),
      child: Row(
        children: [
          _pagerButton(
            icon: Icons.chevron_left_rounded,
            label: '上一页',
            enabled: canGoPrevious,
            onTap: _loadPrevious,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '第 $_page 页',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _loadingMore ? '正在加载' : (_hasMore ? '还有更多回复' : '已显示全部内容'),
                  style: TextStyle(fontSize: 10.5, color: scheme.outline),
                ),
              ],
            ),
          ),
          _pagerButton(
            icon: Icons.chevron_right_rounded,
            label: _loadingMore ? '加载中' : (_hasMore ? '下一页' : '到底了'),
            enabled: canGoNext,
            loading: _loadingMore,
            trailing: true,
            onTap: _loadMore,
          ),
        ],
      ),
    );
  }

  /// 翻页按钮：可点时是主色淡底，到头是灰底，按下有水波纹。
  ///
  /// 原来是 OutlinedButton + FilledButton 拼在一块灰底卡片里，两个大按钮加
  /// 一行页码，看着像网页底部的分页块；换成两侧小胶囊 + 中间页码，和楼层的
  /// 尺度更接近，也不会在列表尾部突然糊上一块灰。
  Widget _pagerButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool trailing = false,
    bool loading = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = enabled ? scheme.primary : scheme.outline;
    final radius = BorderRadius.circular(12);
    final iconWidget = loading
        ? SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : Icon(icon, size: 17, color: fg);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: enabled
              ? scheme.primary.withValues(alpha: isDark ? 0.20 : 0.10)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.32),
          border: Border.all(
            color: enabled
                ? scheme.primary.withValues(alpha: isDark ? 0.34 : 0.24)
                : scheme.outlineVariant.withValues(alpha: 0.32),
            width: 0.8,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!trailing) ...[iconWidget, const SizedBox(width: 3)],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                if (trailing) ...[const SizedBox(width: 3), iconWidget],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _composer() {
    return ReplyComposer(
      controller: _replyController,
      focusNode: _replyFocus,
      replyToAuthor: _replyTarget?.author,
      replyToFloor: _replyTarget?.floorLabel,
      attachmentCount: _replyAttachments.length,
      uploading: _uploading,
      sending: _sending,
      showEmoji: _showEmoji,
      onToggleEmoji: _toggleEmoji,
      onClearReplyTarget: _clearReplyTarget,
      onAttach: _attachReplyImage,
      onSend: _sendReply,
      emojiPanel: EmojiPanel(
        height: 220,
        onSelected: (emoji) => insertAtCursor(_replyController, emoji),
      ),
    );
  }

  /// 仅移除 Discuz 自动插入的编辑记录，保留帖子正文。
/// 不按标记位置截断整段文本：部分模板会把编辑记录放在正文开头，
/// 截断会导致编辑器里的正文被清空。
String _stripEditNotice(String text) {
  var result = text;
  result = result.replaceAll(
    RegExp(r'本帖最后由\s*.+?\s+于\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}\s+编辑', dotAll: true),
    '',
  );
  result = result.replaceAll(RegExp(r'帖子编辑\s*'), '');
  return result.trim();
}

String _plainText(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(div|p|li|blockquote)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// 楼中楼点评输入面板：自带键盘避让，返回输入的文本。
class _CommentSheet extends StatefulWidget {
  const _CommentSheet({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // BottomSheet 在部分屏幕/字体缩放配置下会按子组件的最小宽度测量；
    // 显式约束为屏幕宽度，避免提示文案被挤成逐字竖排。
    return SizedBox(
      width: MediaQuery.sizeOf(context).width,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            GlassField(
              controller: _controller,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              maxLength: 200,
              textInputAction: TextInputAction.newline,
              hintText: widget.hint,
            ),
            const SizedBox(height: 4),
            Text(
              '点评会直接显示在该楼层下方',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _send,
                child: const Text('发送'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 编辑主题或回复。
class _EditPostPage extends StatefulWidget {
  const _EditPostPage({
    required this.fid,
    required this.tid,
    required this.pid,
    required this.formhash,
    required this.subject,
    required this.message,
    required this.isOp,
  });

  final int fid;
  final int tid;
  final int pid;
  final String formhash;
  final String subject;
  final String message;
  final bool isOp;

  @override
  State<_EditPostPage> createState() => _EditPostPageState();
}

enum _EditPanel { emoji, mention, insert, attach }

class _EditAttachment {
  _EditAttachment({required this.name, required this.image});
  final String name;
  final bool image;
  int? aid;
  bool uploading = false;
  String? error;
}

class _EditPostPageState extends State<_EditPostPage> {
  late final TextEditingController _subject = TextEditingController(text: widget.subject);
  late final TextEditingController _message = TextEditingController(text: widget.message);
  bool _saving = false;
  bool _uploading = false;
  String? _error;
  final ImagePicker _imagePicker = ImagePicker();
  _EditPanel? _panel;
  String? _editMediaKind;
  final TextEditingController _mentionController = TextEditingController();
  final TextEditingController _insertUrlController = TextEditingController();
  final TextEditingController _insertLabelController = TextEditingController();
  List<FriendItem> _friends = const <FriendItem>[];
  bool _friendsLoading = false;
  String? _friendsError;
  final List<_EditAttachment> _attachments = <_EditAttachment>[];

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    _mentionController.dispose();
    _insertUrlController.dispose();
    _insertLabelController.dispose();
    super.dispose();
  }

  void _insertAtCursor(String value) {
    final selection = _message.selection;
    final start = selection.isValid ? selection.start : _message.text.length;
    final end = selection.isValid ? selection.end : _message.text.length;
    final text = _message.text.replaceRange(start, end, value);
    _message.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
  }

  void _toggleEditPanel(_EditPanel panel) {
    FocusScope.of(context).unfocus();
    setState(() { _panel = _panel == panel ? null : panel; _editMediaKind = null; });
    if (panel == _EditPanel.mention && _panel == panel) _loadEditFriends();
  }

  Future<void> _loadEditFriends({bool force = false}) async {
    if (_friendsLoading || (!force && _friends.isNotEmpty)) return;
    if (!AppState.instance.isLoggedIn) {
      setState(() => _friendsError = '登录后可读取论坛好友列表');
      return;
    }
    setState(() { _friendsLoading = true; _friendsError = null; });
    try {
      final value = await AppState.instance.repo.fetchFriends();
      if (!mounted) return;
      setState(() { _friends = value; _friendsError = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _friendsError = e is SiteException ? e.message : '好友列表加载失败');
    } finally {
      if (mounted) setState(() => _friendsLoading = false);
    }
  }

  Future<void> _uploadFiles({required bool image}) async {
    if (_uploading || _saving) return;
    try {
      final info = await AppState.instance.repo.fetchComposeInfo(widget.fid);
      if (!mounted) return;
      if (image) {
        final picked = await _imagePicker.pickMultiImage(maxWidth: 1600, imageQuality: 78);
        for (final file in picked) {
          if (!mounted) return;
          final item = _EditAttachment(name: file.name, image: true);
          setState(() { _attachments.add(item); _uploading = true; _error = null; });
          try {
            final aid = await AppState.instance.repo.uploadAttachment(
              bytes: await file.readAsBytes(), filename: file.name,
              uploadHash: info.uploadHash, uid: info.uid, fid: widget.fid,
              referer: AppConfig.uri('forum.php', {'mod':'post','action':'edit','fid':'${widget.fid}','tid':'${widget.tid}','pid':'${widget.pid}','mobile':'2'}).toString(),
              image: true,
            );
            if (!mounted) return;
            item.aid = aid;
            _insertAtCursor('\\n[attachimg]$aid[/attachimg]\\n');
          } catch (e) {
            if (!mounted) return;
            item.error = e is SiteException ? e.message : '图片上传失败';
            setState(() => _error = item.error);
          } finally {
            if (mounted) setState(() { item.uploading = false; _uploading = false; });
          }
        }
      } else {
        // Use the same FilePicker wrapper/API as the publish-post page.
        // This project exposes FilePicker.pickFiles() returning a file list.
        final files = await FilePicker.pickFiles(type: FileType.any);
        if (files.isEmpty) return;
        for (final file in files) {
          if (!mounted) return;
          final item = _EditAttachment(name: file.name, image: false);
          setState(() { _attachments.add(item); _uploading = true; _error = null; });
          try {
            final bytes = await file.readAsBytes();
            final aid = await AppState.instance.repo.uploadAttachment(
              bytes: bytes, filename: file.name,
              uploadHash: info.uploadHash, uid: info.uid, fid: widget.fid,
              referer: AppConfig.uri('forum.php', {'mod':'post','action':'edit','fid':'${widget.fid}','tid':'${widget.tid}','pid':'${widget.pid}','mobile':'2'}).toString(),
              image: false,
            );
            if (!mounted) return;
            item.aid = aid;
            _insertAtCursor('\\n[attach]$aid[/attach]\\n');
          } catch (e) {
            if (!mounted) return;
            item.error = e is SiteException ? e.message : '附件上传失败';
            setState(() => _error = item.error);
          } finally {
            if (mounted) setState(() { item.uploading = false; _uploading = false; });
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is SiteException ? e.message : '上传失败，请重试');
    }
  }

  void _insertEditMention([String? username]) {
    final name = (username ?? _mentionController.text).trim();
    if (name.isEmpty) { setState(() => _error = '请输入要 @ 的用户名'); return; }
    _insertAtCursor('@$name ');
    _mentionController.clear();
    setState(() => _panel = null);
  }

  void _insertEditTag(String tag) {
    _wrapTag(tag);
    setState(() => _panel = null);
  }

  Future<void> _insertEditLink() async {
    final url = _insertUrlController.text.trim();
    final label = _insertLabelController.text.trim();
    if (url.isEmpty) { setState(() => _error = '请输入链接网址'); return; }
    _insertAtCursor('[url=$url]${label.isEmpty ? url : label}[/url]');
    _insertUrlController.clear(); _insertLabelController.clear();
    setState(() => _panel = null);
  }

  Future<void> _insertEditMedia(String kind) async {
    final url = _insertUrlController.text.trim();
    if (url.isEmpty) { setState(() => _error = '请输入链接地址'); return; }
    final tag = switch (kind) {
      'img' => '[img]$url[/img]',
      'audio' => '[audio]$url[/audio]',
      'video' => '[media=x,500,375]$url[/media]',
      'flash' => '[flash=480,400]$url[/flash]',
      _ => url,
    };
    _insertAtCursor(tag);
    _insertUrlController.clear();
    setState(() => _panel = null);
  }

  void _wrapTag(String tag) {
    final selection = _message.selection;
    final start = selection.isValid ? selection.start : _message.text.length;
    final end = selection.isValid ? selection.end : _message.text.length;
    final selected = start < end ? _message.text.substring(start, end) : '';
    final open = '[$tag]';
    final close = '[/$tag]';
    final value = '$open$selected$close';
    _message.value = TextEditingValue(
      text: _message.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + open.length + selected.length),
    );
  }

  Future<void> _save() async {
    // 只有主题正文有标题；回帖保持空标题，别把 `Re: 主题` 写进楼层。
    final subject = widget.isOp ? _subject.text.trim() : '';
    final message = _message.text.trim();
    if (widget.isOp && subject.isEmpty) {
      setState(() => _error = '标题不能为空');
      return;
    }
    if (message.isEmpty) {
      setState(() => _error = '内容不能为空');
      return;
    }
    setState(() {
      _panel = null;
      _saving = true;
      _error = null;
    });
    try {
      await AppState.instance.repo.editPost(
        fid: widget.fid,
        tid: widget.tid,
        pid: widget.pid,
        subject: subject,
        message: message,
        formhash: widget.formhash,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is SiteException ? e.message : '保存失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBusy = _saving || _uploading;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(widget.isOp ? '编辑主题' : '编辑回复'),
        centerTitle: false,
        actions: [
          TextButton.icon(
            onPressed: isBusy ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(_saving ? '保存中' : '保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          children: [
            if (widget.isOp) ...[
              GlassField(
                controller: _subject,
                label: '主题标题',
                hintText: '请输入主题标题',
                leading: Icons.title_rounded,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 24),
            ],
            Row(
              children: [
                Expanded(
                  child: Text('正文内容', style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  )),
                ),
                Text(
                  '支持图片、链接与 BBCode',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GlassCard(
              radius: 18,
              color: scheme.surfaceContainerLow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                      border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65))),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.start,
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _editorTool(Icons.sentiment_satisfied_alt_rounded, '表情', () => _toggleEditPanel(_EditPanel.emoji)),
                        _editorTool(Icons.alternate_email_rounded, '@朋友', () => _toggleEditPanel(_EditPanel.mention)),
                        _editorTool(Icons.send_rounded, '插入', () => _toggleEditPanel(_EditPanel.insert)),
                        _editorTool(Icons.attach_file_rounded, '附件', () => _toggleEditPanel(_EditPanel.attach)),
                        _editorTool(Icons.add_photo_alternate_outlined, '上传图片', _uploading ? null : () => _uploadFiles(image: true)),
                        _editorTool(Icons.format_bold_rounded, '加粗', () => _wrapTag('b')),
                        _editorTool(Icons.format_italic_rounded, '斜体', () => _wrapTag('i')),
                        _editorTool(Icons.format_quote_rounded, '引用', () => _wrapTag('quote')),
                        _editorTool(Icons.code_rounded, '代码', () => _wrapTag('code')),
                      ],
                    ),
                  ),
                  if (_panel != null) _editPanelContent(scheme),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: TextField(
                      controller: _message,
                      minLines: 12,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 15.5, height: 1.65),
                      decoration: InputDecoration(
                        hintText: '在这里编辑正文…',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_uploading) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 4),
              Text('正在上传图片…', style: TextStyle(fontSize: 12, color: scheme.primary)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: TextStyle(fontSize: 12.5, color: scheme.error))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55))),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: isBusy ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded, size: 20),
                    label: Text(_saving ? '正在保存修改…' : '保存修改', style: const TextStyle(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editPanelContent(ColorScheme scheme) {
    Widget shell(Widget child) => Container(
      constraints: const BoxConstraints(maxHeight: 320),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65))),
      ),
      child: SingleChildScrollView(child: child),
    );
    switch (_panel!) {
      case _EditPanel.emoji:
        return EmojiPanel(onSelected: (emoji) => _insertAtCursor(_emojiInsertion(emoji)));
      case _EditPanel.mention:
        final key = _mentionController.text.trim().toLowerCase();
        final friends = _friends.where((f) => key.isEmpty || f.username.toLowerCase().contains(key)).take(12);
        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: GlassField(
                controller: _mentionController,
                hintText: '搜索好友或输入用户名',
                leading: Icons.search_rounded,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _insertEditMention,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('@添加', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ]),
          Row(children: [
            Expanded(child: Text(_friendsError ?? (_friendsLoading ? '正在加载好友…' : '选择好友可插入 @用户名，也可手动输入。'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
            IconButton(onPressed: _friendsLoading ? null : () => _loadEditFriends(force: true), icon: const Icon(Icons.refresh)),
          ]),
          if (_friendsLoading) const LinearProgressIndicator(),
          for (final friend in friends) ListTile(dense: true, title: Text(friend.username),
            leading: const Icon(Icons.alternate_email), onTap: () => _insertEditMention(friend.username)),
        ]));
      case _EditPanel.insert:
        const chips = <(String, String, String)>[
          ('url', '文字链接', 'url'), ('img', '网络图片', 'img'),
          ('audio', 'MP3 音乐', 'audio'), ('video', '网络视频', 'video'),
          ('flash', 'Flash', 'flash'), ('quote', '引用', 'quote'),
          ('code', '代码', 'code'), ('b', '加粗', 'b'), ('i', '斜体', 'i'),
          ('free', '免费信息', 'free'), ('hide', '隐藏内容', 'hide'),
        ];
        final isLink = _editMediaKind == 'url';
        final isMedia = const {'img', 'audio', 'video', 'flash'}.contains(_editMediaKind);
        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final chip in chips)
              ChoiceChip(
                label: Text(chip.$2, style: TextStyle(fontSize: 12,
                  color: _editMediaKind == chip.$1 ? scheme.onPrimaryContainer : scheme.onSurface)),
                backgroundColor: scheme.surface,
                selectedColor: scheme.primaryContainer,
                side: BorderSide(color: _editMediaKind == chip.$1
                  ? scheme.primary.withValues(alpha: 0.65)
                  : scheme.outlineVariant.withValues(alpha: 0.8)),
                selected: _editMediaKind == chip.$1,
                onSelected: (_) {
                  if (const {'quote', 'code', 'b', 'i', 'free', 'hide'}.contains(chip.$1)) {
                    _insertEditTag(chip.$3);
                    return;
                  }
                  setState(() {
                    _editMediaKind = chip.$1;
                    _insertUrlController.clear();
                    _insertLabelController.clear();
                  });
                },
              ),
          ]),
          if (isLink || isMedia) ...[
            const SizedBox(height: 12),
            GlassField(
              controller: _insertUrlController,
              label: isLink ? '链接网址' : '链接 / 媒体地址',
              hintText: 'https://',
              leading: Icons.link_rounded,
              keyboardType: TextInputType.url,
            ),
            if (isLink) ...[
              const SizedBox(height: 10),
              GlassField(
                controller: _insertLabelController,
                label: '链接文字（可留空）',
                leading: Icons.title_rounded,
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: isLink ? _insertEditLink : () => _insertEditMedia(_editMediaKind!),
              icon: const Icon(Icons.add_link_rounded),
              label: Text(isLink ? '插入链接' : '插入媒体内容'))),
          ] else
            Padding(padding: const EdgeInsets.only(top: 10),
              child: Text('选择“文字链接”或媒体类型后，填写地址并点击插入；格式标签会直接包裹选中的正文。',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
        ]));
      case _EditPanel.attach:
        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _uploading ? null : () => _uploadFiles(image: false),
            icon: const Icon(Icons.attach_file), label: Text(_uploading ? '正在上传…' : '添加文件 / 选择附件'))),
          Text('支持多选文件；格式及大小由论坛附件规则决定。上传成功后会在光标处插入附件标记。',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          for (final item in _attachments) ListTile(dense: true,
            leading: Icon(item.error != null ? Icons.error_outline : item.uploading ? Icons.cloud_upload_outlined : item.image ? Icons.image_outlined : Icons.insert_drive_file_outlined),
            title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(item.error ?? (item.uploading ? '上传中' : item.aid == null ? '待上传' : '已上传 · aid ${item.aid}')),
            trailing: IconButton(tooltip: '移除附件', onPressed: item.uploading ? null : () {
              final aid = item.aid;
              if (aid != null) {
                final tag = item.image ? '[attachimg]$aid[/attachimg]' : '[attach]$aid[/attach]';
                _message.text = _message.text.replaceAll(tag, '');
                _message.selection = TextSelection.collapsed(offset: _message.text.length);
              }
              setState(() => _attachments.remove(item));
            }, icon: const Icon(Icons.close_rounded, size: 18))),
        ]));
    }
  }

  String _emojiInsertion(String emoji) => emoji;

  Widget _editorTool(IconData icon, String label, VoidCallback? onPressed) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: (_saving || _uploading) ? null : onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: (_saving || _uploading) ? scheme.outline : scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: (_saving || _uploading) ? scheme.outline : scheme.onSurfaceVariant,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

/// 举报面板。
class ReportSheet extends StatefulWidget {
  const ReportSheet({super.key, required this.floor});

  final String floor;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  static const List<String> _reasons = ForumRepository.reportReasons;

  final TextEditingController _controller = TextEditingController();
  int _reason = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '举报 ${widget.floor}',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          for (var i = 0; i < _reasons.length; i++)
            InkWell(
              onTap: () => setState(() => _reason = i),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                child: Row(
                  children: [
                    Icon(
                      _reason == i ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                      size: 17,
                      color: _reason == i ? scheme.primary : scheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Text(_reasons[i], style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          GlassField(
            controller: _controller,
            minLines: 1,
            maxLines: 3,
            maxLength: 120,
            hintText: '补充说明（可选）',
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop((_reasons[_reason], _controller.text.trim())),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              child: const Text('提交举报', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '举报会提交给版主和管理员处理',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}

/// 打赏结果：勾选的积分项、理由与是否通知作者。
class _RateResult {
  const _RateResult({required this.scores, this.reason = '', this.notify = false});

  final Map<int, int> scores;
  final String reason;
  final bool notify;
}

/// 打赏面板：对齐站点移动模板（头像 + 昵称 + 好评 / 金币 + 理由 + 通知作者）。
class _RateSheet extends StatefulWidget {
  const _RateSheet({
    required this.floor,
    required this.isOp,
    required this.author,
    required this.avatar,
    required this.options,
  });

  final String floor;
  final bool isOp;
  final String author;
  final String avatar;
  final RateOptions options;

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  final TextEditingController _reason = TextEditingController();
  final Map<int, int> _scores = <int, int>{};
  bool _notify = false;

  @override
  void initState() {
    super.initState();
    for (final field in widget.options.fields) {
      _scores[field.id] = 0;
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  int get _total => _scores.values.fold(0, (sum, value) => sum + value);

  void _submit() {
    if (_total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择打赏积分')),
      );
      return;
    }
    final scores = <int, int>{
      for (final entry in _scores.entries)
        if (entry.value != 0) entry.key: entry.value,
    };
    Navigator.of(context).pop(
      _RateResult(
        scores: scores,
        reason: _reason.text.trim(),
        notify: _notify,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close_rounded, size: 20, color: scheme.outline),
              ),
            ),
            UserAvatar(url: widget.avatar, name: widget.author, size: 54),
            const SizedBox(height: 8),
            Text(
              widget.author.isEmpty ? '匿名' : widget.author,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              widget.isOp ? '搬砖不容易，打赏一下楼主吧' : '打赏一下${widget.floor}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            for (final field in widget.options.fields) _fieldRow(field, scheme),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GlassField(
                controller: _reason,
                minLines: 1,
                maxLines: 3,
                maxLength: 100,
                hintText: '说两句鼓励一下吧…',
              ),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: const Text('通知作者', style: TextStyle(fontSize: 14)),
              value: _notify,
              onChanged: (value) => setState(() => _notify = value),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5A5A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: Text(
                    widget.isOp ? '赞赏' : '打赏',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldRow(RateField field, ColorScheme scheme) {
    final ceiling = field.ceiling;
    final exhausted = ceiling <= 0;
    var start = field.min <= 0 ? field.min : 0;
    if (start > ceiling) start = 0;
    final values = <int>{0};
    if (!exhausted) {
      if (field.presets.isNotEmpty) {
        values.addAll(field.presets.where((score) => score >= start && score <= ceiling));
      } else {
        for (var score = start; score <= ceiling; score++) {
          values.add(score);
        }
      }
    }
    final options = values.toList()..sort();
    final current = _scores[field.id] ?? 0;
    final value = options.contains(current) ? current : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      child: Row(
        children: [
          Text(field.label, style: const TextStyle(fontSize: 14.5)),
          const Spacer(),
          SizedBox(
            width: 92,
            child: GlassSelectRow(
              dense: true,
              value: exhausted ? '—' : '$value',
              onTap: exhausted
                  ? () {}
                  : () async {
                      final picked = await showGlassOptionSheet<int>(
                        context,
                        title: field.label,
                        options: [for (final score in options) (score, '$score')],
                        selected: value,
                      );
                      if (picked == null || !mounted) return;
                      setState(() => _scores[field.id] = picked);
                    },
            ),
          ),
          const SizedBox(width: 8),
          Text(
            exhausted ? '已用完' : '剩 ${field.left}',
            style: TextStyle(
              fontSize: 10.5,
              color: exhausted ? scheme.error : scheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
