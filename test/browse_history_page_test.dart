import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/services/browse_history.dart';
import 'package:mt_forum/ui/pages/browse_history_page.dart';

/// 内存版历史存储：widget 测试跑在 FakeAsync 里，真实文件 IO 不会完成，
/// 磁盘读写本身由 browse_history_test.dart 覆盖，这里只验证界面行为。
class _MemoryHistory extends BrowseHistory {
  _MemoryHistory() : super(directory: () async => Directory.systemTemp);

  final List<BrowseHistoryEntry> entries = <BrowseHistoryEntry>[];

  @override
  Future<List<BrowseHistoryEntry>> list() async => List<BrowseHistoryEntry>.of(entries);

  @override
  Future<void> record({
    required int tid,
    required String title,
    String boardName = '',
    String author = '',
    String cover = '',
    String postedAt = '',
    int replies = 0,
    int views = 0,
    DateTime? viewedAt,
  }) async {
    if (tid <= 0) return;
    entries.removeWhere((entry) => entry.tid == tid);
    entries.insert(
      0,
      BrowseHistoryEntry(
        tid: tid,
        title: title.trim().isEmpty ? '未命名帖子' : title.trim(),
        viewedAt: viewedAt ?? DateTime.now(),
        boardName: boardName,
        author: author,
        cover: cover,
        postedAt: postedAt,
        replies: replies,
        views: views,
      ),
    );
    revision.value++;
  }

  @override
  Future<void> remove(int tid) async {
    entries.removeWhere((entry) => entry.tid == tid);
    revision.value++;
  }

  @override
  Future<void> clear() async {
    if (entries.isEmpty) return;
    entries.clear();
    revision.value++;
  }
}

void main() {
  late _MemoryHistory history;

  setUp(() => history = _MemoryHistory());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: BrowseHistoryPage(history: history)));
    await tester.pumpAndSettle();
  }

  testWidgets('没有记录时给出空状态引导', (tester) async {
    await pump(tester);
    expect(find.text('还没有浏览记录'), findsOneWidget);
    expect(find.textContaining('打开任意帖子后会自动记录'), findsOneWidget);
    expect(find.byTooltip('清空浏览历史'), findsNothing);
  });

  testWidgets('按日期分组展示记录，并显示版块与作者', (tester) async {
    final now = DateTime.now();
    await history.record(
      tid: 168143,
      title: '【多栈实战】某黑产软件全链路逆向实录 (下)',
      boardName: '逆向',
      author: 'Bin',
      replies: 26,
      viewedAt: now,
    );
    await history.record(
      tid: 175647,
      title: '视频演示帖',
      boardName: '综合',
      author: 'mt',
      viewedAt: now.subtract(const Duration(days: 1)),
    );

    await pump(tester);

    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.textContaining('全链路逆向实录'), findsOneWidget);
    expect(find.text('视频演示帖'), findsOneWidget);
    expect(find.text('逆向 · Bin'), findsOneWidget);
    expect(find.textContaining('26 回复'), findsOneWidget);
    expect(find.byTooltip('清空浏览历史'), findsOneWidget);
  });

  testWidgets('搜索按标题 / 作者 / 版块过滤', (tester) async {
    await history.record(tid: 1, title: '逆向实录', boardName: '逆向', author: 'Bin');
    await history.record(tid: 2, title: '视频演示帖', boardName: '综合', author: 'mt');
    await pump(tester);

    await tester.enterText(find.byType(TextField), '视频');
    await tester.pumpAndSettle();
    expect(find.text('视频演示帖'), findsOneWidget);
    expect(find.text('逆向实录'), findsNothing);

    await tester.enterText(find.byType(TextField), 'bin');
    await tester.pumpAndSettle();
    expect(find.text('逆向实录'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '不存在的关键词');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的浏览记录'), findsOneWidget);
  });

  testWidgets('左滑删除单条记录', (tester) async {
    await history.record(tid: 1, title: '要删掉的帖子');
    await history.record(tid: 2, title: '保留的帖子');
    await pump(tester);

    await tester.drag(find.text('要删掉的帖子'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('要删掉的帖子'), findsNothing);
    expect(find.text('保留的帖子'), findsOneWidget);
    expect(find.textContaining('已从浏览历史移除'), findsOneWidget);
    expect(history.entries.map((e) => e.tid), [2]);
  });

  testWidgets('清空需要确认，确认后列表回到空状态', (tester) async {
    await history.record(tid: 1, title: '唯一一条');
    await pump(tester);

    await tester.tap(find.byTooltip('清空浏览历史'));
    await tester.pumpAndSettle();
    expect(find.text('清空浏览历史？'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('唯一一条'), findsOneWidget);

    await tester.tap(find.byTooltip('清空浏览历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();

    expect(find.text('还没有浏览记录'), findsOneWidget);
    expect(history.entries, isEmpty);
  });
}
