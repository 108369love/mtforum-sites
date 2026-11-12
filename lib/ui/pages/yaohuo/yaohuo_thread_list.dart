import 'dart:async';
import 'dart:math' as math;

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
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    // 离底部 200px 就预加载下一页，拉到底就能接着看。
    if (position.pixels >= position.maxScrollExtent - 200) {
      if (!_loadingMore && !_loading && _error == null && !_notLoggedIn) {
        unawaited(_loadMore());
      }
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

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
      if (widget.cards) unawaited(_enrichTimes());
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

  /// 列表页只有「今天 晚上」这种半天粒度，精确到分要回帖子页取。
  /// 只补卡片模式下的前 6 条、3 并发，其余保留站点原始文案。
  Future<void> _enrichTimes() async {
    final targets = _items
        .where((item) => item.publishedAt == null)
        .take(6)
        .toList();
    if (targets.isEmpty) return;
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < targets.length) {
        final index = cursor++;
        final item = targets[index];
        final time = await YaohuoRepository.instance.fetchPublishedAt(item.url);
        if (time == null || !mounted) continue;
        final position = _items.indexWhere((candidate) => candidate.url == item.url);
        if (position < 0) continue;
        setState(() => _items[position] = _items[position].copyWith(publishedAt: time));
      }
    }

    await Future.wait(<Future<void>>[
      for (var i = 0; i < math.min(3, targets.length); i++) worker(),
    ]);
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

  String? _boardName(int? classId) {
    if (classId == null) return null;
    for (final board in YaohuoRepository.boards) {
      if (board.id == classId) return board.name;
    }
    return null;
  }

  String _clock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String _relative(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${time.month} 月 ${time.day} 日';
  }

  Widget _card(BuildContext context, YaohuoThreadItem item, ColorScheme scheme) {
    final initial = item.author.isEmpty ? '妖' : item.author.substring(0, 1);
    final board = _boardName(item.classId);
    final published = item.publishedAt;
    final timeText = published == null
        ? item.time
        : <String>[_relative(published), _clock(published)].where((part) => part.isNotEmpty).join(' · ');
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
              crossAxisAlignment: CrossAxisAlignment.center,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.author.isEmpty ? '妖友' : item.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      if (timeText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            timeText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                if (board != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      board,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary),
                    ),
                  ),
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
          controller: _scroll,
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
        controller: _scroll,
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
