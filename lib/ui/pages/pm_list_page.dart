import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/state_views.dart';
import '../widgets/user_avatar.dart';
import 'login_page.dart';
import 'pm_chat_page.dart';
import '../navigation/app_routes.dart';

/// 私信会话列表。
class PmListPage extends StatefulWidget {
  const PmListPage({super.key});

  @override
  State<PmListPage> createState() => _PmListPageState();
}

class _PmListPageState extends State<PmListPage> {
  final List<PmConversation> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AppState.instance.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = null;
        _items.clear();
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AppState.instance.repo.fetchPmConversations();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is SiteException ? e.message : '加载私信失败，请稍后重试';
      });
    }
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      noSwipeRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true) await _load();
  }

  Future<void> _openChat(PmConversation conversation) async {
    await Navigator.of(context).push(appRoute(
      builder: (_) => PmChatPage(uid: conversation.uid, name: conversation.name),
    ));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topInset = glassTopInset(context);
    return Scaffold(
      // 会话列表从玻璃顶栏背后滚过。
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('私信'),
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
                        edgeOffset: topInset,
                        child: _items.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                children: [
                                  SizedBox(height: topInset + 82),
                                  const EmptyView(text: '还没有私信', icon: Icons.mail_outline_rounded),
                                ],
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                padding: EdgeInsets.fromLTRB(14, topInset + 8, 14, 24),
                                itemCount: _items.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                                ),
                                itemBuilder: (context, index) {
                                  final item = _items[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    leading: UserAvatar(url: item.avatar, name: item.name, size: 46),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.name.isEmpty ? 'UID ${item.uid}' : item.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        if (item.time.isNotEmpty)
                                          Text(
                                            item.time,
                                            style: TextStyle(fontSize: 10, color: scheme.outline),
                                          ),
                                      ],
                                    ),
                                    subtitle: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.preview,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                                          ),
                                        ),
                                        if (item.unread)
                                          Container(
                                            width: 7,
                                            height: 7,
                                            margin: const EdgeInsets.only(left: 6),
                                            decoration: BoxDecoration(
                                              color: scheme.error,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    onTap: () => _openChat(item),
                                  );
                                },
                              ),
                      ),
      ),
    );
  }

  Widget _loginHint(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mail_outline_rounded, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text('登录后查看私信', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _openLogin, child: const Text('立即登录')),
        ],
      ),
    );
  }
}
