import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/state_views.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/user_avatar.dart';
import 'login_page.dart';
import 'pm_chat_page.dart';
import 'pm_list_page.dart';
import 'thread_page.dart';
import 'user_page.dart';
import '../navigation/app_routes.dart';
import '../widgets/glass_dialog.dart';

/// 原生提醒列表页。
///
/// 数据来自站点提醒接口（`home.php?mod=space&do=notice&view=...`），但列表、
/// 空状态、错误处理、以及点进去的落地页全部由 Flutter 原生绘制：
/// 主题提醒进入帖子页，互动提醒进入用户页，私信提醒进入会话页。
class NativeNoticeCategoryPage extends StatefulWidget {
  const NativeNoticeCategoryPage({
    super.key,
    required this.title,
    this.view = '',
  });

  final String title;

  /// Discuz 提醒分类：interactive / friend / system / app，空表示全部提醒。
  final String view;

  @override
  State<NativeNoticeCategoryPage> createState() => _NativeNoticeCategoryPageState();
}

class _NativeNoticeCategoryPageState extends State<NativeNoticeCategoryPage> {
  final ScrollController _scroll = ScrollController();
  List<NoticeItem> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    if (!AppState.instance.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _items = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AppState.instance.repo.fetchNotices(view: widget.view);
      if (!mounted) return;
      setState(() {
        _items = items;
        _page = 1;
        _hasMore = items.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is SiteException ? e.message : '加载消息失败，请检查网络后重试';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await AppState.instance.repo.fetchNotices(view: widget.view, page: _page + 1);
      if (!mounted) return;
      setState(() {
        final known = _items.map((item) => '${item.target.name}|${item.tid}|${item.uid}|${item.title}|${item.time}').toSet();
        final fresh = next
            .where((item) => known.add('${item.target.name}|${item.tid}|${item.uid}|${item.title}|${item.time}'))
            .toList();
        if (fresh.isNotEmpty) {
          _items = [..._items, ...fresh];
          _page += 1;
          _hasMore = true;
        } else {
          _hasMore = false;
        }
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      noSwipeRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true) await _load();
  }

  /// 每条提醒的目标页面在解析阶段就已确定，这里只做分发，不再出现「无法识别」的死路。
  Future<void> _openItem(NoticeItem item) async {
    switch (item.target) {
      case NoticeTarget.thread:
        await Navigator.of(context).push(appRoute(
          builder: (_) => ThreadPage(tid: item.tid),
        ));
      case NoticeTarget.user:
        await Navigator.of(context).push(appRoute(
          builder: (_) => UserPage(uid: item.uid),
        ));
      case NoticeTarget.pm:
        if (item.uid > 0) {
          await Navigator.of(context).push(appRoute(
            builder: (_) => PmChatPage(uid: item.uid),
          ));
        } else {
          await Navigator.of(context).push(appRoute(builder: (_) => const PmListPage()));
        }
      case NoticeTarget.none:
        // 系统提醒没有落地页，直接把完整正文展示成原生弹窗。
        if (!mounted) return;
        await showGlassDialog<void>(
          context: context,
          builder: (context) => GlassDialog(
            title: Text(widget.title),
            content: Text(item.title),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了')),
            ],
          ),
        );
    }
  }

  IconData _iconFor(NoticeItem item) => switch (item.target) {
        NoticeTarget.thread => Icons.forum_outlined,
        NoticeTarget.user => Icons.person_outline_rounded,
        NoticeTarget.pm => Icons.mail_outline_rounded,
        NoticeTarget.none => Icons.notifications_none_rounded,
      };

  bool _showAvatar(NoticeItem item) {
    if (item.target != NoticeTarget.user) return false;
    final url = item.avatar;
    return url.isNotEmpty && (url.contains('avatar') || url.contains('uc_server'));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Text(widget.title),
        actions: [
          if (AppState.instance.isLoggedIn)
            IconButton(
              tooltip: '刷新',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: !AppState.instance.isLoggedIn
            ? _loginHint(scheme)
            : _loading
                ? SkeletonView(kind: SkeletonKind.row, topInset: glassTopInset(context))
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _items.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 140),
                                  EmptyView(text: '暂无新的提醒', icon: Icons.notifications_off_outlined),
                                ],
                              )
                            : ListView.separated(
                                controller: _scroll,
                                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                padding: EdgeInsets.only(top: glassTopInset(context) + 6, bottom: 24),
                                itemCount: _items.length + (_loadingMore ? 1 : 0),
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  indent: 70,
                                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                                ),
                                itemBuilder: (context, index) {
                                  if (index >= _items.length) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 18),
                                      child: Center(child: SizedBox(
                                        width: 22, height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )),
                                    );
                                  }
                                  return _row(context, scheme, _items[index]);
                                },
                              ),
                      ),
      ),
    );
  }

  Widget _row(BuildContext context, ColorScheme scheme, NoticeItem item) {
    final leading = _showAvatar(item)
        ? UserAvatar(url: item.avatar, name: item.title, size: 42)
        : Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: item.unread
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _iconFor(item),
              size: 21,
              color: item.unread ? scheme.primary : scheme.onSurfaceVariant,
            ),
          );

    final subtitle = item.time.isEmpty ? null : Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            item.time,
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
        );

    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(kPageGutter, 6, 12, 6),
      leading: leading,
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: item.unread ? FontWeight.w700 : FontWeight.w500,
          height: 1.35,
        ),
      ),
      subtitle: subtitle,
      trailing: item.hasTarget
          ? Icon(Icons.chevron_right_rounded, color: scheme.outline)
          : null,
      onTap: () => _openItem(item),
    );
  }

  Widget _loginHint(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none_rounded, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text('登录后查看消息提醒', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _openLogin, child: const Text('立即登录')),
        ],
      ),
    );
  }
}
