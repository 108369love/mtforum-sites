import 'package:flutter/material.dart';
import '../../services/offline_thread_cache.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/state_views.dart';
import '../widgets/post_html_view.dart';
import '../navigation/app_routes.dart';
import '../widgets/glass_dialog.dart';

class OfflineCachePage extends StatefulWidget {
  const OfflineCachePage({super.key});
  @override State<OfflineCachePage> createState() => _OfflineCachePageState();
}
class _OfflineCachePageState extends State<OfflineCachePage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  @override void initState() { super.initState(); _refresh(); }
  Future<void> _refresh() async {
    final data = await OfflineThreadCache.instance.list();
    if (mounted) setState(() { _items = data; _loading = false; });
  }
  Future<void> _delete(Map<String, dynamic> item) async {
    final tid = int.tryParse('${item['tid']}'); if (tid == null) return;
    final ok = await showGlassDialog<bool>(context: context, builder: (c) => GlassDialog(
      title: const Text('删除离线缓存？'), content: Text('「${item['title'] ?? '帖子'}」将从本机删除。'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除'))]));
    if (ok == true) { await OfflineThreadCache.instance.delete(tid); await _refresh(); }
  }
  Future<void> _clearAll() async {
    if (_items.isEmpty) return;
    final ok = await showGlassDialog<bool>(context: context, builder: (c) => GlassDialog(
      title: const Text('清理全部离线缓存？'), content: const Text('将删除本机保存的所有帖子缓存，且无法撤销。'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('全部清理'))]));
    if (ok == true) { await OfflineThreadCache.instance.clear(); await _refresh(); }
  }
  void _open(Map<String, dynamic> item) => Navigator.push(context, appRoute<void>(builder: (_) => _OfflineThreadDetail(item: item)));
  @override Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(extendBodyBehindAppBar: true, appBar: GlassAppBar(title: const Text('离线缓存'), actions: [IconButton(tooltip: '清理全部缓存', onPressed: _items.isEmpty ? null : _clearAll, icon: const Icon(Icons.delete_sweep_outlined))]),
      body: _loading ? SkeletonView(kind: SkeletonKind.row, topInset: glassTopInset(context)) : _items.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.offline_pin_outlined, size: 52, color: scheme.onSurfaceVariant), const SizedBox(height: 12), const Text('还没有离线缓存'), const SizedBox(height: 6), Text('打开帖子，选择「缓存帖子供离线阅读」', style: TextStyle(color: scheme.onSurfaceVariant))]))
        : RefreshIndicator(onRefresh: _refresh, child: ListView.separated(padding: glassPagePadding(context, top: 2), itemCount: _items.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, i) {
          final item = _items[i]; final date = DateTime.tryParse('${item['cachedAt'] ?? ''}')?.toLocal();
          final count = item['posts'] is List ? (item['posts'] as List).length : 0;
          final size = OfflineThreadCache.instance.estimateBytes(item);
          return Card(clipBehavior: Clip.antiAlias, child: ListTile(leading: const Icon(Icons.offline_pin_outlined), title: Text('${item['title'] ?? '未命名帖子'}', maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${item['boardName'] ?? ''} · $count 条已缓存内容\n缓存于：${date ?? '未知'} · ${(size / 1024).toStringAsFixed(1)} KB'), isThreeLine: true, onTap: () => _open(item),
            trailing: IconButton(tooltip: '删除缓存', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(item))));
        })));
  }
}
class _OfflineThreadDetail extends StatelessWidget {
  const _OfflineThreadDetail({required this.item});
  final Map<String, dynamic> item;
  @override Widget build(BuildContext context) {
    final posts = item['posts'] is List ? item['posts'] as List : const <dynamic>[];
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(extendBodyBehindAppBar: true, appBar: const GlassAppBar(title: Text('离线阅读')), body: ListView(padding: glassPagePadding(context, top: 2), children: [
      Card(color: scheme.primaryContainer.withValues(alpha: .24), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${item['title'] ?? '帖子'}', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
        Text('${item['boardName'] ?? ''} · ${item['author'] ?? ''} · ${item['time'] ?? ''}'),
        const SizedBox(height: 6), Text('离线副本 · ${posts.length} 条已缓存内容', style: TextStyle(color: scheme.onSurfaceVariant))]))),
      for (final value in posts) if (value is Map) Card(margin: const EdgeInsets.only(top: 8), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text('${value['author'] ?? '用户'}', style: const TextStyle(fontWeight: FontWeight.w700))), Text(value['floor'] == 1 ? '主题正文' : '${value['floor'] ?? ''}#', style: TextStyle(fontSize: 12, color: scheme.primary))]),
        const SizedBox(height: 10), PostHtmlView(html: '${value['html'] ?? ''}', images: const <String>[]),
        if ((value['comments'] as List?)?.isNotEmpty == true)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: .45), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('楼中楼评论', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              for (final comment in (value['comments'] as List))
                if (comment is Map)
                  Padding(padding: const EdgeInsets.only(top: 5), child: Text('${comment['author'] ?? '用户'}：${comment['text'] ?? ''}')),
            ]),
          ),
      ])))
    ]));
  }
}
