import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../state/app_state.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_controls.dart';
import '../widgets/state_views.dart';
import '../widgets/thread_feed.dart';
import '../navigation/app_routes.dart';

/// 标签广场：点击标签查看该标签下的主题。
class TagsPage extends StatefulWidget {
  const TagsPage({super.key});

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  final List<(String, int)> _tags = [];
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
      final tags = await AppState.instance.repo.fetchTags();
      if (!mounted) return;
      setState(() {
        _tags
          ..clear()
          ..addAll(tags);
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
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('标签'),
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
                    child: _tags.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                            padding: EdgeInsets.only(top: glassTopInset(context)),
                            children: const [
                              SizedBox(height: 90),
                              EmptyView(text: '暂无标签'),
                            ],
                          )
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                            padding: glassPagePadding(context, top: 14),
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  // 和搜索页的筛选胶囊同一套玻璃：标签本身是「被强调的对象」，
                                  // 所以用 accent 语义色，而不是中性白玻璃。
                                  for (final tag in _tags)
                                    GlassPill(
                                      label: tag.$1,
                                      tone: GlassPillTone.accent,
                                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                                      onTap: () => Navigator.of(context).push(
                                        appRoute(
                                          builder: (_) => _TagThreadsPage(id: tag.$2, name: tag.$1),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                  ),
      ),
    );
  }
}

class _TagThreadsPage extends StatelessWidget {
  const _TagThreadsPage({required this.id, required this.name});

  final int id;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(title: Text('#$name', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        top: false,
        child: ThreadFeed(
          loader: (page) => AppState.instance.repo.fetchTagThreads(id, page: page),
          emptyText: '该标签下暂无主题',
          padding: glassPagePadding(context, top: 10),
        ),
      ),
    );
  }
}
