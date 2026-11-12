import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../pages/thread_page.dart';
import 'back_to_top.dart';
import 'state_views.dart';
import 'thread_card.dart';
import '../navigation/app_routes.dart';

/// 通用主题流：首屏加载、下拉刷新、触底加载更多。
class ThreadFeed extends StatefulWidget {
  const ThreadFeed({
    super.key,
    required this.loader,
    this.header,
    this.pinnedHeader,
    this.pinnedHeaderHeight = 56,
    this.pinnedHeaderFrost = 0,
    this.emptyText = '这里还没有内容',
    this.enabled = true,
    this.padding = const EdgeInsets.fromLTRB(14, 8, 14, 24),
    this.onRefresh,
    this.controller,
    this.doubleTapToTop = false,
    this.refreshOffset,
  });

  final Future<List<ThreadSummary>> Function(int page) loader;
  final Widget? header;

  /// 会吸顶的横条：随列表上滑，滚到顶部后钉住不再消失。
  ///
  /// 和 [header] 的区别在于它单独占一个 sliver，滚动到顶端后贴在屏幕上方，
  /// 适合放「最新 / 热门 / 精华」这类需要随时切换的筛选条。
  final Widget? pinnedHeader;

  /// 吸顶条的高度。SliverPersistentHeader 需要提前知道占位高度，
  /// 所以这里必须是个固定值。
  final double pinnedHeaderHeight;

  /// 吸顶条底板的磨砂强度，0 表示不磨砂（实色底）。
  ///
  /// 传正数时整条底板会做一层高斯模糊，帖子从下面滚过时会被虚化，
  /// 配合吸顶条自己的半透明玻璃容器就是毛玻璃效果。
  final double pinnedHeaderFrost;

  final String emptyText;
  final bool enabled;
  final EdgeInsets padding;
  final Future<void> Function()? onRefresh;

  /// 外部传进来的滚动控制器，页面级的「双击顶栏回顶」要用。
  final ScrollController? controller;

  /// 双击帖子卡片回到顶部。
  ///
  /// 只有滚过大半屏之后才挂上双击识别，回到顶部就摘掉——否则单击进帖子
  /// 每次都要等双击判定超时，点起来会发钝。
  ///
  /// 双击只认卡片本身：整页包一层识别器会把「点一下没反应又补一下」
  /// 当成双击，尤其是滑了一点点之后，很容易莫名其妙被弹回顶部。
  final bool doubleTapToTop;

  /// 下拉刷新指示器相对列表顶部的偏移。
  ///
  /// 顶栏做成玻璃之后，指示器默认那点偏移会藏在顶栏背后，得由页面把
  /// 「状态栏 + 顶栏」的高度传进来。
  final double? refreshOffset;

  @override
  State<ThreadFeed> createState() => _ThreadFeedState();
}

class _ThreadFeedState extends State<ThreadFeed> {
  final List<ThreadSummary> _items = [];
  late final ScrollController _scroll;
  late final bool _ownsScroll;
  bool _loading = false;
  bool _initialized = false;
  bool _hasMore = true;
  bool _farFromTop = false;
  String? _error;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _scroll = widget.controller ?? ScrollController();
    _ownsScroll = widget.controller == null;
    _scroll.addListener(_onScroll);
    if (widget.enabled) _loadFirst();
  }

  @override
  void didUpdateWidget(covariant ThreadFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) _loadFirst();
  }

  @override
  void dispose() {
    if (_ownsScroll) _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // 双击回顶只在滚过大半屏后才启用：刚滑一点点时双击本来也没什么意义，
    // 挂上反而会把「点一下没反应再点一下」误判成双击弹回顶部。
    final far = _scroll.position.pixels > _doubleTapThreshold;
    if (far != _farFromTop) setState(() => _farFromTop = far);
    if (_loading || !_hasMore || _error != null) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 500) {
      _loadMore();
    }
  }

  /// 双击回顶的启用距离，跟着视口高度走，顺手夹在合理区间里。
  double get _doubleTapThreshold {
    if (!_scroll.hasClients) return 360;
    final viewport = _scroll.position.viewportDimension;
    if (!viewport.isFinite || viewport <= 0) return 360;
    return (viewport * 0.6).clamp(160.0, 720.0);
  }

  Future<void> _loadFirst() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final batch = await widget.loader(1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(batch);
        _page = 1;
        _hasMore = batch.length >= 10;
        _initialized = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _message(e);
        _initialized = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final batch = await widget.loader(_page + 1);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _items.addAll(batch);
        _hasMore = batch.length >= 10;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _message(e);
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await widget.onRefresh?.call();
    _error = null;
    await _loadFirst();
  }

  String _message(Object error) => error is SiteException ? error.message : '加载失败，请稍后重试';

  Widget _skeletonCard(ColorScheme scheme) => Container(
        height: 132,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 30, height: 30, decoration: BoxDecoration(color: scheme.surfaceContainerHighest, shape: BoxShape.circle)),
              const SizedBox(width: 9),
              Container(width: 78, height: 10, color: scheme.surfaceContainerHighest),
            ]),
            const SizedBox(height: 14),
            Container(height: 13, color: scheme.surfaceContainerHighest),
            const SizedBox(height: 8),
            FractionallySizedBox(widthFactor: 0.62, child: Container(height: 13, color: scheme.surfaceContainerHighest)),
          ],
        ),
      );

  /// 列表尾部的状态：空、出错、加载中、到底。
  Widget _tail(ColorScheme scheme, bool showSkeleton) {
    if (_items.isEmpty && _initialized && _error == null) {
      return SizedBox(
        height: 320,
        child: EmptyView(text: widget.emptyText),
      );
    }
    if (_error != null) {
      return ErrorView(
        message: _error!,
        compact: _items.isNotEmpty,
        onRetry: () {
          if (_items.isEmpty) {
            _loadFirst();
          } else {
            _loadMore();
          }
        },
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (!_hasMore && _items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text('— 已经到底啦 —', style: TextStyle(fontSize: 11.5, color: scheme.outline)),
        ),
      );
    }
    return const SizedBox(height: 20);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showSkeleton = _loading && _items.isEmpty && _error == null;

    // header 与吸顶条各自占一个 sliver，列表项放进 SliverPadding，
    // 这样吸顶条能独立钉在顶部，不会跟着帖子一起滚走。
    final slivers = <Widget>[
      if (widget.header != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              widget.padding.left,
              widget.padding.top,
              widget.padding.right,
              0,
            ),
            child: widget.header,
          ),
        ),
      if (widget.pinnedHeader != null)
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedHeaderDelegate(
            height: widget.pinnedHeaderHeight,
            background: Theme.of(context).scaffoldBackgroundColor,
            frost: widget.pinnedHeaderFrost,
            dividerColor: scheme.outlineVariant.withValues(alpha: 0.35),
            child: Padding(
              padding: EdgeInsets.only(
                left: widget.padding.left,
                right: widget.padding.right,
              ),
              child: widget.pinnedHeader,
            ),
          ),
        ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          widget.padding.left,
          // 没有 header 的页面（我的主题 / 我的回复 / 我的收藏、标签下的帖子）
          // 顶栏留白只能由列表自己撑：以前这里恒为 0，第一条帖子就直接顶到
          // 玻璃顶栏背后，头像和用户名被糊掉半行。有 header 时留白由 header
          // 那块 SliverToBoxAdapter 负责，这里再补一次会空出双重间距。
          widget.header == null && widget.pinnedHeader == null ? widget.padding.top : 0,
          widget.padding.right,
          widget.padding.bottom,
        ),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (showSkeleton) {
                if (index < 5) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _skeletonCard(scheme),
                  );
                }
                return _tail(scheme, showSkeleton);
              }

              if (index < _items.length) {
                final thread = _items[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: ThreadCard(
                    thread: thread,
                    onDoubleTap:
                        widget.doubleTapToTop && _farFromTop ? () => scrollToTop(_scroll) : null,
                    onTap: () => Navigator.of(context).push(
                      appRoute(builder: (_) => ThreadPage(tid: thread.tid, title: thread.title)),
                    ),
                  ),
                );
              }
              return _tail(scheme, showSkeleton);
            },
            childCount: (showSkeleton ? 5 : _items.length) + 1,
          ),
        ),
      ),
    ];

    return RefreshIndicator(
      onRefresh: _refresh,
      edgeOffset: widget.refreshOffset ?? (widget.header == null ? 0 : 8),
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: slivers,
      ),
    );
  }
}

/// 固定高度的吸顶条。
///
/// 用 OverflowBox 把内容按自然高度居中，超出部分裁掉——系统字体放大时
/// 筛选条不会报 RenderFlex overflow，只是上下各裁掉一点。
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHeaderDelegate({
    required this.height,
    required this.background,
    required this.child,
    this.frost = 0,
    this.dividerColor = const Color(0x00000000),
  });

  final double height;
  final Color background;
  final Widget child;

  /// 底板磨砂强度，>0 时底板改成「模糊 + 半透明」，让下面的帖子透上来。
  final double frost;
  final Color dividerColor;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final frosted = frost > 0;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: frosted ? background.withValues(alpha: 0.62) : background,
        border: frosted
            ? Border(bottom: BorderSide(color: dividerColor, width: 0.6))
            : null,
      ),
      child: OverflowBox(
        alignment: Alignment.center,
        minHeight: 0,
        maxHeight: 200,
        child: child,
      ),
    );
    return ClipRect(
      child: frosted
          // 先模糊背后的滚动内容，再压一层半透明底色，不然帖子文字会穿过
          // 筛选条看得清清楚楚。
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: frost, sigmaY: frost, tileMode: TileMode.clamp),
              child: content,
            )
          : content,
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) =>
      oldDelegate.height != height ||
      oldDelegate.background != background ||
      oldDelegate.frost != frost ||
      oldDelegate.dividerColor != dividerColor ||
      oldDelegate.child != child;
}
