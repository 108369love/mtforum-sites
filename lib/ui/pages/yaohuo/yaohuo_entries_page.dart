import 'package:flutter/material.dart';

import '../../../data/yaohuo_repository.dart';
import '../../navigation/app_routes.dart';
import '../internal_browser_page.dart';
import 'yaohuo_thread_list.dart';

/// 「帖子」入口：站点给的地址按帖子列表解析。
class YaohuoMyThreadsPage extends StatelessWidget {
  const YaohuoMyThreadsPage({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: '用浏览器打开',
            onPressed: () => Navigator.of(context).push(
              appRoute(builder: (_) => InternalBrowserPage(url: url, title: title)),
            ),
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
        ],
      ),
      body: YaohuoThreadListView(
        key: ValueKey<String>('yaohuo-mine-$url'),
        loader: (page) => YaohuoRepository.instance.fetchThreadListFromUrl(url, page: page),
        emptyText: '这里还没有帖子',
      ),
    );
  }
}

/// 「地盘 / 空间」入口：用户资料页，解析成字段表。
class YaohuoUserPage extends StatefulWidget {
  const YaohuoUserPage({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  State<YaohuoUserPage> createState() => _YaohuoUserPageState();
}

class _YaohuoUserPageState extends State<YaohuoUserPage> {
  Map<String, String> _info = <String, String>{};
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
      final info = await YaohuoRepository.instance.fetchUserInfo(widget.url);
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
        _failed = info.isEmpty;
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
    Navigator.of(context).push(
      appRoute(builder: (_) => InternalBrowserPage(url: widget.url, title: widget.title)),
    );
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
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              children: [
                if (_failed) ...[
                  Icon(Icons.person_off_outlined, size: 44, color: scheme.outline),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      '这个页面没能解析出资料',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(onPressed: _openBrowser, child: const Text('用浏览器打开')),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [scheme.primary.withValues(alpha: 0.90), scheme.primary.withValues(alpha: 0.60)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.white24,
                          child: Builder(builder: (context) {
                            final name = _info['昵称'] ?? _info['用户ID'] ?? '?';
                            final initial = name.isEmpty ? '?' : name.substring(0, 1);
                            return Text(
                              initial,
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                            );
                          }),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _info['昵称'] ?? '妖火用户',
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  if ((_info['等级'] ?? '').isNotEmpty) _info['等级']!,
                                  if ((_info['头衔'] ?? '').isNotEmpty) _info['头衔']!,
                                  if ((_info['身份'] ?? '').isNotEmpty) _info['身份']!,
                                ].join(' · '),
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        children: [
                          for (var i = 0; i < _info.length; i++) ...[
                            if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.45)),
                            ListTile(
                              dense: true,
                              title: Text(_info.keys.elementAt(i), style: const TextStyle(fontSize: 13)),
                              trailing: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 200),
                                child: Text(
                                  _info.values.elementAt(i),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// 「信箱」入口：没有固定结构的列表页，按通用链接列表解析，点开走浏览器。
class YaohuoLinkListPage extends StatefulWidget {
  const YaohuoLinkListPage({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  State<YaohuoLinkListPage> createState() => _YaohuoLinkListPageState();
}

class _YaohuoLinkListPageState extends State<YaohuoLinkListPage> {
  List<({String title, String url, String extra})> _rows = <({String title, String url, String extra})>[];
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
      final rows = await YaohuoRepository.instance.fetchLinkList(widget.url);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _failed = rows.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _open(String url, String title) {
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
          IconButton(
            tooltip: '用浏览器打开',
            onPressed: () => _open(widget.url, widget.title),
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: _rows.length + (_failed ? 1 : 0),
              separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.35)),
              itemBuilder: (context, index) {
                if (index >= _rows.length) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.inbox_outlined, size: 40, color: scheme.outline),
                        const SizedBox(height: 10),
                        Text('这里没有解析出列表', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => _open(widget.url, widget.title),
                          child: const Text('用浏览器打开'),
                        ),
                      ],
                    ),
                  );
                }
                final row = _rows[index];
                return ListTile(
                  leading: Icon(Icons.chat_bubble_outline_rounded, size: 20, color: scheme.primary),
                  title: Text(row.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                  subtitle: row.extra.isEmpty ? null : Text(row.extra, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => _open(row.url, row.title),
                );
              },
            ),
    );
  }
}
