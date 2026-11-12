import 'package:flutter/material.dart';

import '../../../core/yaohuo_session.dart';
import '../../../data/yaohuo_repository.dart';
import '../../navigation/app_routes.dart';
import '../internal_browser_page.dart';
import 'yaohuo_login_page.dart';
import 'yaohuo_thread_page.dart';

/// 妖火网原生首页：新帖列表。
class YaohuoHomePage extends StatefulWidget {
  const YaohuoHomePage({super.key});

  @override
  State<YaohuoHomePage> createState() => _YaohuoHomePageState();
}

class _YaohuoHomePageState extends State<YaohuoHomePage> {
  final List<YaohuoThreadItem> _items = <YaohuoThreadItem>[];
  bool _loading = true;
  bool _notLoggedIn = false;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;

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
      final items = await YaohuoRepository.instance.fetchNewThreads(page: 1);
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
      final items = await YaohuoRepository.instance.fetchNewThreads(page: _page + 1);
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

  void _openBrowser({String url = 'https://yaohuo.me/', String title = '妖火网'}) {
    Navigator.of(context).push(appRoute(builder: (_) => InternalBrowserPage(url: url, title: title)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('妖火网'),
        actions: [
          if (_notLoggedIn)
            TextButton(onPressed: _openLogin, child: const Text('登录'))
          else
            IconButton(tooltip: '刷新', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
          IconButton(
            tooltip: '用浏览器打开',
            onPressed: () => _openBrowser(),
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(scheme),
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notLoggedIn) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
        children: [
          Icon(Icons.lock_outline_rounded, size: 44, color: scheme.outline),
          const SizedBox(height: 12),
          const Center(child: Text('妖火的内容需要登录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          const SizedBox(height: 8),
          Text(
            '登录页带人机验证，原生请求过不去，所以登录交给内置浏览器完成：'
            '登录一次之后，原生页面就能直接用这份会话读帖子。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.6, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _openLogin, child: const Text('登录妖火')),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => _openBrowser(url: 'https://yaohuo.me/waplogin.aspx', title: '登录妖火'),
            child: const Text('在浏览器里登录'),
          ),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
        children: [
          Icon(Icons.cloud_off_rounded, size: 44, color: scheme.outline),
          const SizedBox(height: 12),
          Center(child: Text('读取失败', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.error))),
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          FilledButton(onPressed: _load, child: const Text('重试')),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
        children: const [Center(child: Text('这里还没有帖子'))],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _items.length + 1,
      separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.35)),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(onPressed: _loadMore, child: const Text('加载更多')),
            ),
          );
        }
        final item = _items[index];
        return ListTile(
          title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [item.author, item.time, if (item.reply.isNotEmpty) '回复 ${item.reply}', if (item.read.isNotEmpty) '阅 ${item.read}']
                  .where((part) => part.isNotEmpty)
                  .join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
          onTap: () => _openThread(item),
        );
      },
    );
  }
}
