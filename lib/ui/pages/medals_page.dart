import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_controls.dart';
import '../widgets/state_views.dart';
import '../widgets/user_avatar.dart';
import 'user_page.dart';
import '../navigation/app_routes.dart';
import '../widgets/glass_dialog.dart';

/// 勋章中心：勋章目录 + 最近获得记录。
class MedalsPage extends StatefulWidget {
  const MedalsPage({super.key});

  @override
  State<MedalsPage> createState() => _MedalsPageState();
}

class _MedalsPageState extends State<MedalsPage> {
  List<MedalItem> _medals = [];
  List<MedalRecord> _records = [];
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
      final (medals, records) = await AppState.instance.repo.fetchMedals();
      if (!mounted) return;
      setState(() {
        _medals = medals;
        _records = records;
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

  void _showMedal(MedalItem item) {
    showGlassDialog<void>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.image.isNotEmpty)
              Image.network(item.image, width: 64, height: 64, fit: BoxFit.contain),
            const SizedBox(height: 10),
            Text(item.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (item.desc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(item.desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, height: 1.5)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('知道了')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('勋章中心'),
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
            ? SkeletonView(kind: SkeletonKind.grid, topInset: glassTopInset(context))
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: glassPagePadding(context, top: 12),
                      children: [
                        _sectionTitle(scheme, '勋章目录', '${_medals.length} 枚'),
                        const SizedBox(height: 10),
                        if (_medals.isEmpty)
                          EmptyView(text: '站点暂未开放勋章', icon: Icons.military_tech_outlined)
                        else
                          GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            child: GridView.builder(
                              shrinkWrap: true,
                              // 不写 padding 时网格会继承 MediaQuery 的安全区，
                              // 这一页开了 extendBodyBehindAppBar，会凭空多出顶栏那 100dp。
                              padding: EdgeInsets.zero,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisExtent: 70,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 4,
                              ),
                              itemCount: _medals.length,
                              itemBuilder: (context, index) => _medalTile(scheme, _medals[index]),
                            ),
                          ),
                        const SizedBox(height: 20),
                        _sectionTitle(scheme, '勋章记录', '最近 ${_records.length} 条'),
                        const SizedBox(height: 10),
                        if (_records.isEmpty)
                          const EmptyView(text: '暂无勋章获得记录', icon: Icons.history_rounded)
                        else
                          for (final record in _records) ...[
                            _recordTile(scheme, record),
                            const SizedBox(height: 8),
                          ],
                      ],
                    ),
                  ),
      ),
    );
  }

  /// 单枚勋章：图标 + 名字，点开看详情。
  Widget _medalTile(ColorScheme scheme, MedalItem item) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showMedal(item),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (item.image.isNotEmpty)
            Image.network(
              item.image,
              width: 38,
              height: 38,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.military_tech_outlined,
                size: 34,
                color: scheme.primary,
              ),
            )
          else
            Icon(Icons.military_tech_outlined, size: 34, color: scheme.primary),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ColorScheme scheme, String title, String trailing) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Text(trailing, style: TextStyle(fontSize: 11, color: scheme.outline)),
      ],
    );
  }

  Widget _recordTile(ColorScheme scheme, MedalRecord record) {
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          appRoute(builder: (_) => UserPage(uid: record.uid, name: record.name)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              UserAvatar(url: record.avatar, name: record.name, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      record.medal,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(record.time, style: TextStyle(fontSize: 10.5, color: scheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}
