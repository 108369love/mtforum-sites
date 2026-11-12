import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/state_views.dart';
import 'user_page.dart';
import '../navigation/app_routes.dart';

/// 小黑屋：站点公示的违规用户列表（forum.php?mod=misc&action=showdarkroom）。
class BlackHousePage extends StatefulWidget {
  const BlackHousePage({super.key});

  @override
  State<BlackHousePage> createState() => _BlackHousePageState();
}

class _BlackHousePageState extends State<BlackHousePage> {
  final List<DarkRoomEntry> _items = [];
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
      final items = await AppState.instance.repo.fetchDarkRoom();
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('小黑屋'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? SkeletonView(kind: SkeletonKind.row, topInset: glassTopInset(context))
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: glassPagePadding(context, top: 12),
                      itemCount: _items.isEmpty ? 2 : _items.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (index == 0) return _header(scheme);
                        if (_items.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 60),
                            child: EmptyView(text: '暂时没有人被关进小黑屋'),
                          );
                        }
                        final item = _items[index - 1];
                        return _tile(scheme, item);
                      },
                    ),
                  ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.gavel_rounded, size: 18, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _items.isEmpty
                  ? '站点只公示被禁言或禁止访问的用户，处罚由版主执行。'
                  : '共 ${_items.length} 条公示记录。站点只公示操作行为、过期时间与操作时间，未公开具体处罚原因。',
              style: TextStyle(fontSize: 12, height: 1.5, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(ColorScheme scheme, DarkRoomEntry item) {
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: item.uid <= 0
            ? null
            : () => Navigator.of(context).push(
                  appRoute(builder: (_) => UserPage(uid: item.uid, name: item.name)),
                ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: scheme.errorContainer,
                child: Text(
                  item.name.isEmpty ? '?' : item.name.substring(0, 1),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onErrorContainer),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.action,
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: scheme.error),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (item.expiry.isNotEmpty) item.expiry,
                        if (item.time.isNotEmpty) '操作于 ${item.time}',
                      ].join(' · '),
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
