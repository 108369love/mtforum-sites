import 'package:flutter/material.dart';

import '../../../data/yaohuo_repository.dart';
import '../../navigation/app_routes.dart';
import 'yaohuo_login_page.dart';
import 'yaohuo_thread_page.dart';

/// 妖火的帖子列表：首页、板块、搜索共用一套。
///
/// 只负责「一页一页往下拉」这件事，取数交给传进来的 [loader]。
class YaohuoThreadListView extends StatefulWidget {
  const YaohuoThreadListView({
    super.key,
    required this.loader,
    this.emptyText = '这里还没有帖子',
    this.cards = false,
  });

  final Future<List<YaohuoThreadItem>> Function(int page) loader;
  final String emptyText;

  /// 卡片样式（首页用，和 MT论坛 的 feed 一致）；列表样式给板块/搜索用。
  final bool cards;

  @override
  State<YaohuoThreadListView> createState() => _YaohuoThreadListViewState();
}

class _YaohuoThreadListViewState extends State<YaohuoThreadListView> with AutomaticKeepAliveClientMixin {
  final List<YaohuoThreadItem> _items = <YaohuoThreadItem>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _notLoggedIn = false;
  String? _error;
  int _page = 1;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _notLoggedIn = false;
    });
    try {
      final items = await widget.loader(1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _page = 1;
        _loading = false;
      });
    } on YaohuoNotLoggedIn {
      if (!mounted) return;
      setState(() {
        _notLoggedIn = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final items = await widget.loader(_page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _page += 1;
        _loadingMore = false;
      });
    } on YaohuoNotLoggedIn {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _notLoggedIn = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('加载失败：$e')));
    }
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(appRoute(builder: (_) => const YaohuoLoginPage()));
    if (ok == true) await _load();
  }

  Future<void> _openThread(YaohuoThreadItem item) async {
    await Navigator.of(context).push(appRoute(builder: (_) => YaohuoThreadPage(url: item.url, title: item.title)));
  }

  Widget _card(BuildContext context, YaohuoThreadItem item, ColorScheme scheme) {
    final initial = item.author.isEmpty ? '妖' : item.author.substring(0, 1);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openThread(item),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: scheme.primary.withValues(alpha: 0.14),
                  child: Text(
                    initial,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.author.isEmpty ? '妖友' : item.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                if (item.time.isNotEmpty)
                  Text(item.time, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.35),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 3),
                Text(item.reply.isEmpty ? '0' : item.reply, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 12),
                Icon(Icons.visibility_outlined, size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 3),
                Text(item.read.isEmpty ? '0' : item.read, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_notLoggedIn) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
          children: [
            Icon(Icons.lock_outline_rounded, size: 44, color: scheme.outline),
            const SizedBox(height: 12),
            const Center(child: Text('妖火的内容需要登录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            const SizedBox(height: 10),
            Text(
              '登录页带人机验证，原生请求过不去，所以登录交给内置浏览器完成；'
              '登录一次之后原生列表就能直接读。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.6, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _openLogin, child: const Text('登录妖火')),
          ],
        ),
      );
    }
    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
          children: [
            Icon(Icons.cloud_off_rounded, size: 44, color: scheme.outline),
            const SizedBox(height: 12),
            Center(child: Text('读取失败', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.error))),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 18),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
          children: [Center(child: Text(widget.emptyText))],
        ),
      );
    }
    if (widget.cards) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          itemCount: _items.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == _items.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: _loadingMore
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(onPressed: _loadMore, child: const Text('加载更多')),
                ),
              );
            }
            return _card(context, _items[index], scheme);
          },
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 12),
        itemCount: _items.length + 1,
        separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.35)),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: _loadingMore
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(onPressed: _loadMore, child: const Text('加载更多')),
              ),
            );
          }
          final item = _items[index];
          return ListTile(
            title: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                <String>[
                  item.author,
                  item.time,
                  if (item.reply.isNotEmpty) '回复 ${item.reply}',
                  if (item.read.isNotEmpty) '阅 ${item.read}',
                ].where((part) => part.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
            onTap: () => _openThread(item),
          );
        },
      ),
    );
  }
}
