import 'package:flutter/material.dart';

import '../../../data/yaohuo_repository.dart';
import '../../navigation/app_routes.dart';
import 'yaohuo_login_page.dart';
import 'yaohuo_thread_page.dart';

/// 妖火的帖子列表：首页、板块、搜索共用一套。
///
/// 只负责「一页一页往下拉」这件事，取数交给传进来的 [loader]。
class YaohuoThreadListView extends StatefulWidget {
  const YaohuoThreadListView({super.key, required this.loader, this.emptyText = '这里还没有帖子'});

  final Future<List<YaohuoThreadItem>> Function(int page) loader;
  final String emptyText;

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
