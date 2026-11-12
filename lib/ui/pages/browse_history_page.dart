import 'package:flutter/material.dart';

import '../../services/browse_history.dart';
import '../widgets/smart_image.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/state_views.dart';
import '../widgets/glass_controls.dart';
import 'thread_page.dart';
import '../navigation/app_routes.dart';
import '../widgets/glass_dialog.dart';

/// 浏览历史：按时间倒序列出打开过的帖子，点一下直接回到帖子。
class BrowseHistoryPage extends StatefulWidget {
  const BrowseHistoryPage({super.key, this.history});

  /// 便于测试注入；默认用全局实例。
  final BrowseHistory? history;

  @override
  State<BrowseHistoryPage> createState() => _BrowseHistoryPageState();
}

class _BrowseHistoryPageState extends State<BrowseHistoryPage> {
  final TextEditingController _search = TextEditingController();

  List<BrowseHistoryEntry> _items = const <BrowseHistoryEntry>[];
  bool _loading = true;
  String _query = '';

  BrowseHistory get _history => widget.history ?? BrowseHistory.instance;

  @override
  void initState() {
    super.initState();
    _history.revision.addListener(_onHistoryChanged);
    _refresh();
  }

  @override
  void dispose() {
    _history.revision.removeListener(_onHistoryChanged);
    _search.dispose();
    super.dispose();
  }

  void _onHistoryChanged() {
    if (mounted) _refresh();
  }

  Future<void> _refresh() async {
    final items = await _history.list();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  List<BrowseHistoryEntry> get _visible {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items
        .where((entry) =>
            entry.title.toLowerCase().contains(query) ||
            entry.author.toLowerCase().contains(query) ||
            entry.boardName.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _open(BrowseHistoryEntry entry) async {
    await Navigator.of(context).push(appRoute<void>(
      builder: (_) => ThreadPage(tid: entry.tid, title: entry.title),
    ));
    // 回来后浏览时间已刷新，重新排序。
    await _refresh();
  }

  Future<void> _remove(BrowseHistoryEntry entry) async {
    await _history.remove(entry.tid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已从浏览历史移除「${entry.title}」')),
    );
  }

  Future<void> _clearAll() async {
    if (_items.isEmpty) return;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('清空浏览历史？'),
        content: const Text('只会删除本机的浏览记录，不影响收藏和离线缓存。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    await _history.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('浏览历史已清空')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('浏览历史'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: '清空浏览历史',
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: _loading
          ? SkeletonView(kind: SkeletonKind.row, topInset: glassTopInset(context))
          : _items.isEmpty
              ? _emptyState(scheme)
              : Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(kPageGutter, glassTopInset(context) + 10, kPageGutter, 6),
                      child: GlassSearchField(
                        controller: _search,
                        hintText: '搜索标题、作者或版块',
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    Expanded(
                      child: visible.isEmpty
                          ? Center(
                              child: Text(
                                '没有匹配的浏览记录',
                                style: TextStyle(color: scheme.onSurfaceVariant),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _refresh,
                              child: _buildList(context, visible, scheme),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _emptyState(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 54, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            const Text('还没有浏览记录'),
            const SizedBox(height: 6),
            Text(
              '打开任意帖子后会自动记录在这里，方便回头再看',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<BrowseHistoryEntry> entries, ColorScheme scheme) {
    // 按天分组：今天 / 昨天 / 更早，组内保持最近浏览在前。
    final rows = <Object>[];
    String? currentLabel;
    for (final entry in entries) {
      final label = _dayLabel(entry.viewedAt);
      if (label != currentLabel) {
        rows.add(label);
        currentLabel = label;
      }
      rows.add(entry);
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(kPageGutter, 4, kPageGutter, 24),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row is String) {
          return Padding(
            padding: EdgeInsets.only(top: index == 0 ? 4 : 16, bottom: 8, left: 2),
            child: Text(
              row,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final entry = row as BrowseHistoryEntry;
        return _entryCard(context, entry, scheme);
      },
    );
  }

  Widget _entryCard(BuildContext context, BrowseHistoryEntry entry, ColorScheme scheme) {
    final meta = <String>[
      if (entry.boardName.isNotEmpty) entry.boardName,
      if (entry.author.isNotEmpty) entry.author,
    ];
    return Dismissible(
      key: ValueKey<int>(entry.tid),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => _remove(entry),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlassCard(
          radius: 16,
          onTap: () => _open(entry),
          padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _thumbnail(entry, scheme),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.35),
                      ),
                      const SizedBox(height: 6),
                      if (meta.isNotEmpty)
                        Text(
                          meta.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(Icons.history_rounded, size: 12.5, color: scheme.outline),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '浏览于 ${_timeLabel(entry.viewedAt)}'
                              '${entry.replies > 0 ? ' · ${entry.replies} 回复' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: scheme.outline),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12, left: 4),
                  child: Icon(Icons.chevron_right_rounded, color: scheme.outline, size: 20),
                ),
              ],
            ),
        ),
      ),
    );
  }

  Widget _thumbnail(BrowseHistoryEntry entry, ColorScheme scheme) {
    final cover = entry.cover.trim();
    if (cover.isEmpty) {
      return Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.article_outlined, size: 22, color: scheme.onSurfaceVariant),
      );
    }
    return SmartImage(
      url: cover,
      width: 54,
      height: 54,
      fit: BoxFit.cover,
      radius: BorderRadius.circular(12),
      cacheWidth: 162,
    );
  }

  String _dayLabel(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff < 7) return '$diff 天前';
    if (local.year == now.year) return '${local.month} 月 ${local.day} 日';
    return '${local.year} 年 ${local.month} 月 ${local.day} 日';
  }

  String _timeLabel(DateTime time) {
    final local = time.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
    return sameDay ? '$hh:$mm' : '${local.month} 月 ${local.day} 日 $hh:$mm';
  }
}
