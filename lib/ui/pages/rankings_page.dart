import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../state/app_state.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/state_views.dart';

/// 排行榜：用户 / 主题 / 版块。
class RankingsPage extends StatefulWidget {
  const RankingsPage({super.key});

  @override
  State<RankingsPage> createState() => _RankingsPageState();
}

class _RankingsPageState extends State<RankingsPage> {
  static const List<(String, String)> _types = [
    ('member', '用户'),
    ('thread', '主题'),
    ('forum', '版块'),
  ];

  String _type = 'member';
  final List<(String, String)> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AppState.instance.repo.fetchRanking(_type);
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
        _error = e is SiteException ? e.message : '加载失败，请稍后重试';
      });
    }
  }

  void _select(String type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _items.clear();
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('排行榜')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              // 固定的三段切换器跟着顶栏往下让，正文才不会压在玻璃上。
              padding: EdgeInsets.fromLTRB(kPageGutter, glassTopInset(context) + 10, kPageGutter, 6),
              child: Row(
                children: [
                  for (final type in _types)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _select(type.$1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _type == type.$1
                                  ? scheme.primary.withValues(alpha: 0.12)
                                  : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                type.$2,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: _type == type.$1 ? scheme.primary : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              // 上方三段切换器已经让过顶栏，这里不再重复让位。
              child: _loading
                  ? const SkeletonView(kind: SkeletonKind.row)
                  : _error != null
                      ? ErrorView(message: _error!, onRetry: _load)
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: _items.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                  children: const [
                                    SizedBox(height: 90),
                                    EmptyView(text: '暂无排行数据'),
                                  ],
                                )
                              : ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                  padding: const EdgeInsets.fromLTRB(kPageGutter, 6, kPageGutter, 24),
                                  itemCount: _items.length,
                                  separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                                  ),
                                  itemBuilder: (context, index) {
                                    final item = _items[index];
                                    final rank = index + 1;
                                    final medal = switch (rank) {
                                      1 => const Color(0xFFE0A020),
                                      2 => const Color(0xFF9AA3AE),
                                      3 => const Color(0xFFB87333),
                                      _ => scheme.outline,
                                    };
                                    return ListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      leading: Container(
                                        width: 26,
                                        height: 26,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: rank <= 3 ? medal.withValues(alpha: 0.16) : Colors.transparent,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          '$rank',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: rank <= 3 ? medal : scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        item.$1,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                      trailing: item.$2.isEmpty
                                          ? null
                                          : Text(item.$2, style: TextStyle(fontSize: 11.5, color: scheme.primary)),
                                    );
                                  },
                                ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
