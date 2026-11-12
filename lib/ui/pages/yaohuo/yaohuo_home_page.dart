import 'package:flutter/material.dart';

import '../../../data/yaohuo_repository.dart';
import '../../navigation/app_routes.dart';
import '../internal_browser_page.dart';
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

/// 板块列表。
class YaohuoBoardsPage extends StatelessWidget {
  const YaohuoBoardsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('版块')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (var i = 0; i < YaohuoRepository.boards.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
                    ListTile(
                      leading: Icon(Icons.forum_outlined, size: 20, color: scheme.primary),
                      title: Text(
                        YaohuoRepository.boards[i].name,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('classid ${YaohuoRepository.boards[i].id}', style: const TextStyle(fontSize: 11)),
                      trailing: Icon(Icons.chevron_right_rounded, size: 20, color: scheme.outline),
                      onTap: () => Navigator.of(context).push(
                        appRoute(
                          builder: (_) => YaohuoBoardPage(
                            classId: YaohuoRepository.boards[i].id,
                            name: YaohuoRepository.boards[i].name,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
