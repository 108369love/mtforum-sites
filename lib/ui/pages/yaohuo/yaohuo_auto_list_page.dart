import 'package:flutter/material.dart';

import '../../../data/yaohuo_repository.dart';
import '../../navigation/app_routes.dart';
import '../internal_browser_page.dart';
import 'yaohuo_thread_page.dart';

/// 「收藏 / 好友」这类站点自带的列表页：先按帖子列表解析，不行再按链接列表，
/// 都解析不出来就把页面丢给浏览器。
class YaohuoAutoListPage extends StatefulWidget {
  const YaohuoAutoListPage({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  State<YaohuoAutoListPage> createState() => _YaohuoAutoListPageState();
}

class _YaohuoAutoListPageState extends State<YaohuoAutoListPage> {
  List<YaohuoThreadItem> _threads = <YaohuoThreadItem>[];
  List<({String title, String url, String extra})> _links = <({String title, String url, String extra})>[];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final threads = await YaohuoRepository.instance.fetchThreadListFromUrl(widget.url);
      if (!mounted) return;
      if (threads.isNotEmpty) {
        setState(() {
          _threads = threads;
          _links = <({String title, String url, String extra})>[];
          _loading = false;
        });
        return;
      }
      final links = await YaohuoRepository.instance.fetchLinkList(widget.url);
      if (!mounted) return;
      setState(() {
        _threads = <YaohuoThreadItem>[];
        _links = links;
        _loading = false;
        _failed = links.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _openBrowser() {
    Navigator.of(context).push(appRoute(builder: (_) => InternalBrowserPage(url: widget.url, title: widget.title)));
  }

  void _openThread(YaohuoThreadItem item) {
    Navigator.of(context).push(appRoute(builder: (_) => YaohuoThreadPage(url: item.url, title: item.title)));
  }

  void _openLink(String url, String title) {
    Navigator.of(context).push(appRoute(builder: (_) => InternalBrowserPage(url: url, title: title)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(tooltip: '刷新', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
          IconButton(tooltip: '用浏览器打开', onPressed: _openBrowser, icon: const Icon(Icons.open_in_browser_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
                  children: [
                    Icon(Icons.inbox_outlined, size: 44, color: scheme.outline),
                    const SizedBox(height: 10),
                    Center(child: Text('这个页面没能解析出列表', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant))),
                    const SizedBox(height: 14),
                    FilledButton(onPressed: _openBrowser, child: const Text('用浏览器打开')),
                  ],
                )
              : ListView.separated(
                  itemCount: _threads.isNotEmpty ? _threads.length : _links.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.35)),
                  itemBuilder: (context, index) {
                    if (_threads.isNotEmpty) {
                      final item = _threads[index];
                      return ListTile(
                        title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: item.author.isEmpty && item.time.isEmpty
                            ? null
                            : Text(
                                <String>[item.author, item.time].where((s) => s.isNotEmpty).join(' · '),
                                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                              ),
                        onTap: () => _openThread(item),
                      );
                    }
                    final row = _links[index];
                    return ListTile(
                      leading: Icon(Icons.link_rounded, size: 20, color: scheme.primary),
                      title: Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                      subtitle: row.extra.isEmpty ? null : Text(row.extra, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _openLink(row.url, row.title),
                    );
                  },
                ),
    );
  }
}
