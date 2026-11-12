import 'package:flutter/material.dart';

import '../../../data/yaohuo_repository.dart';
import '../../navigation/app_routes.dart';
import '../internal_browser_page.dart';
import 'yaohuo_compose_page.dart';
import 'yaohuo_search_page.dart';
import 'yaohuo_thread_list.dart';

/// 妖火首页：最新 / 精华 两条流。
class YaohuoHomePage extends StatelessWidget {
  const YaohuoHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('妖火网'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '最新'),
              Tab(text: '精华'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '发帖',
              onPressed: () => Navigator.of(context).push(appRoute(builder: (_) => const YaohuoComposePage())),
              icon: const Icon(Icons.add_rounded),
            ),
            IconButton(
              tooltip: '用浏览器打开',
              onPressed: () => Navigator.of(context).push(
                appRoute(builder: (_) => const InternalBrowserPage(url: 'https://yaohuo.me/', title: '妖火网')),
              ),
              icon: const Icon(Icons.open_in_browser_rounded),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            YaohuoThreadListView(
              key: const PageStorageKey<String>('yaohuo-new'),
              loader: (page) => YaohuoRepository.instance.fetchThreads(
                action: YaohuoRepository.actionNew,
                page: page,
              ),
            ),
            YaohuoThreadListView(
              key: const PageStorageKey<String>('yaohuo-good'),
              loader: (page) => YaohuoRepository.instance.fetchThreads(
                action: YaohuoRepository.actionGood,
                page: page,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个板块的帖子列表。
class YaohuoBoardPage extends StatelessWidget {
  const YaohuoBoardPage({super.key, required this.classId, required this.name});

  final int classId;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: YaohuoThreadListView(
        key: PageStorageKey<String>('yaohuo-board-$classId'),
        loader: (page) => YaohuoRepository.instance.fetchThreads(
          action: YaohuoRepository.actionClass,
          classId: classId,
          page: page,
        ),
        emptyText: '这个板块还没有帖子',
      ),
    );
  }
}

/// 板块列表：按妖火论坛新版布局做的——顶部搜索条 + 发帖、两列卡片、分组。
class YaohuoBoardsPage extends StatefulWidget {
  const YaohuoBoardsPage({super.key});

  @override
  State<YaohuoBoardsPage> createState() => _YaohuoBoardsPageState();
}

class _YaohuoBoardsPageState extends State<YaohuoBoardsPage> {
  static const List<int> _communityIds = <int>[201, 197, 177, 240, 204, 203, 213];
  static const List<int> _serviceIds = <int>[199, 198];

  final List<({int id, String name})> _extra = <({int id, String name})>[];
  final TextEditingController _search = TextEditingController();
  bool _loadingMore = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<({int id, String name})> _pick(List<int> ids) {
    final list = <({int id, String name})>[];
    for (final id in ids) {
      for (final board in YaohuoRepository.boards) {
        if (board.id == id) list.add(board);
      }
    }
    return list;
  }

  List<({int id, String name})> get _others {
    final used = <int>{..._communityIds, ..._serviceIds};
    return _extra.where((board) => !used.contains(board.id)).toList();
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final boards = await YaohuoRepository.instance.fetchBoardsFromSite();
      if (!mounted) return;
      setState(() {
        _extra
          ..clear()
          ..addAll(boards);
        _loadingMore = false;
      });
      if (boards.isEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('站点页面里没解析到更多板块')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('加载板块失败：$e')));
    }
  }

  void _submitSearch() {
    final text = _search.text.trim();
    Navigator.of(context).push(appRoute(builder: (_) => YaohuoSearchPage(initialQuery: text)));
  }

  void _openBoard(({int id, String name}) board) {
    Navigator.of(context).push(appRoute(builder: (_) => YaohuoBoardPage(classId: board.id, name: board.name)));
  }

  IconData _icon(int id) {
    switch (id) {
      case 201:
        return Icons.cloud_outlined;
      case 197:
        return Icons.code_rounded;
      case 177:
        return Icons.coffee_outlined;
      case 240:
        return Icons.image_outlined;
      case 204:
        return Icons.lightbulb_outline_rounded;
      case 203:
        return Icons.wifi_rounded;
      case 213:
        return Icons.quiz_outlined;
      case 199:
        return Icons.settings_outlined;
      case 198:
        return Icons.report_outlined;
      default:
        return Icons.forum_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final community = <({int id, String name})>[..._pick(_communityIds), ..._others];
    final service = _pick(_serviceIds);
    return Scaffold(
      appBar: AppBar(
        title: const Text('版块'),
        actions: [
          IconButton(
            tooltip: '发帖',
            onPressed: () => Navigator.of(context).push(appRoute(builder: (_) => const YaohuoComposePage())),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 26),
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                Text('标题', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                Icon(Icons.expand_more_rounded, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Container(width: 1, height: 18, color: scheme.outlineVariant.withValues(alpha: 0.6)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: '善用搜索',
                      hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    ),
                    onSubmitted: (_) => _submitSearch(),
                  ),
                ),
                InkWell(
                  onTap: _submitSearch,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.search_rounded, size: 20, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('综合论坛', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: scheme.onSurface)),
          const SizedBox(height: 10),
          _grid(context, community),
          if (service.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('服务中心', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: scheme.onSurface)),
            const SizedBox(height: 10),
            _grid(context, service),
          ],
          const SizedBox(height: 14),
          Center(
            child: _loadingMore
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton.icon(
                    onPressed: _loadMore,
                    icon: const Icon(Icons.unfold_more_rounded, size: 18),
                    label: const Text('更多板块'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, List<({int id, String name})> boards) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.75,
      children: [
        for (final board in boards)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openBoard(board),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_icon(board.id), size: 18, color: scheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      board.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
