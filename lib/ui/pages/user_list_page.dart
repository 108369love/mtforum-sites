import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../navigation/app_routes.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/state_views.dart';
import '../widgets/user_avatar.dart';
import 'login_page.dart';
import 'user_page.dart';

/// 列表加载器：`page` 从 1 开始，返回该页用户。不分页的实现忽略这个参数。
typedef UserListLoader = Future<List<FriendItem>> Function(int page);

/// 给页面改列表的口子：取消关注后把行删掉、改完备注把行换掉。
class UserListHandle {
  UserListHandle._(this._state);

  final _UserListPageState _state;

  /// 用新的用户数据替换掉同一 uid 的行。
  void replace(FriendItem user) => _state._replace(user);

  /// 把某个用户从列表里移除（取消关注）。
  void remove(int uid) => _state._remove(uid);

  /// 重新拉一遍列表。
  Future<void> reload() => _state._load();
}

/// 用户列表页：我的好友 / 我的粉丝 / 我的关注共用。
///
/// 这三个页面原来是三份几乎一样的代码（187 / 234 / 255 行），加载、分页、
/// 登录态、空态、行布局各写一遍，改一处要同步三处。这里把公共部分收进来，
/// 页面只需要给出「标题、数据源、空态文案、行右侧的操作」。
class UserListPage extends StatefulWidget {
  const UserListPage({
    super.key,
    required this.title,
    required this.loader,
    required this.emptyText,
    required this.loginHint,
    required this.subtitle,
    this.emptyIcon = Icons.person_outline_rounded,
    this.loginIcon = Icons.group_outlined,
    this.paged = true,
    this.actions,
  });

  final String title;
  final UserListLoader loader;
  final String emptyText;
  final String loginHint;
  final IconData emptyIcon;
  final IconData loginIcon;

  /// 是否支持滚动到底部继续加载。好友列表一次给全，不需要。
  final bool paged;

  /// 副标题：一般是「关注 6 · 粉丝 12」或备注。
  final String Function(FriendItem user) subtitle;

  /// 行右侧的操作按钮。不给就显示一个箭头。
  final List<Widget> Function(BuildContext context, FriendItem user, UserListHandle handle)? actions;

  @override
  State<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  final ScrollController _scroll = ScrollController();
  List<FriendItem> _items = const [];
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
    final state = AppState.instance;
    if (!state.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = const [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.loader(1);
      if (!mounted) return;
      setState(() {
        _items = items;
        _page = 1;
        _hasMore = widget.paged && items.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is SiteException ? e.message : '加载列表失败，请稍后重试';
      });
    }
  }

  Future<void> _loadMore() async {
    if (!widget.paged || _loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await widget.loader(_page + 1);
      if (!mounted) return;
      setState(() {
        // 站点有时会把最后一页重复返回，按 uid 去重，没有新数据就认定到底了。
        final known = _items.map((item) => item.uid).toSet();
        final fresh = next.where((item) => known.add(item.uid)).toList();
        if (fresh.isEmpty) {
          _hasMore = false;
        } else {
          _items = [..._items, ...fresh];
          _page += 1;
        }
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _replace(FriendItem user) {
    final index = _items.indexWhere((item) => item.uid == user.uid);
    if (index < 0) return;
    setState(() {
      _items = [..._items]..[index] = user;
    });
  }

  void _remove(int uid) {
    setState(() => _items = _items.where((item) => item.uid != uid).toList());
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      noSwipeRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true) await _load();
  }

  void _openUser(FriendItem user) {
    Navigator.of(context).push(
      appRoute(builder: (_) => UserPage(uid: user.uid, name: user.username)),
    );
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
                        child: _items.isEmpty ? _empty() : _list(scheme),
                      ),
      ),
    );
  }

  Widget _empty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: EdgeInsets.only(top: glassTopInset(context) + 90),
      children: [EmptyView(text: widget.emptyText, icon: widget.emptyIcon)],
    );
  }

  Widget _list(ColorScheme scheme) {
    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: EdgeInsets.only(top: glassTopInset(context) + 6, bottom: 24),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: kPageGutter + 44 + 16,
        color: scheme.outlineVariant.withValues(alpha: 0.4),
      ),
      itemBuilder: (context, index) {
        if (index >= _items.length) return _moreIndicator();
        return _row(scheme, _items[index]);
      },
    );
  }

  Widget _moreIndicator() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _row(ColorScheme scheme, FriendItem user) {
    final actions = widget.actions?.call(context, user, UserListHandle._(this));
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(kPageGutter, 6, 10, 6),
      leading: UserAvatar(url: user.avatar, name: user.username, size: 44),
      title: Text(
        user.username,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        widget.subtitle(user),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, color: scheme.outline),
      ),
      trailing: actions == null || actions.isEmpty
          ? Icon(Icons.chevron_right_rounded, color: scheme.outline)
          : Row(mainAxisSize: MainAxisSize.min, children: actions),
      onTap: () => _openUser(user),
    );
  }

  Widget _loginHint(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.loginIcon, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(widget.loginHint, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _openLogin, child: const Text('立即登录')),
        ],
      ),
    );
  }
}

/// 统一的副标题：「关注 6 · 粉丝 12」，两边都是 0 时退回 UID。
String userCountsSubtitle(FriendItem user) {
  final parts = <String>[
    if (user.following > 0) '关注 ${user.following}',
    if (user.followers > 0) '粉丝 ${user.followers}',
  ];
  return parts.isEmpty ? 'UID ${user.uid}' : parts.join('  ·  ');
}
