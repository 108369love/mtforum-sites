import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/models.dart';
import 'package:mt_forum/ui/widgets/thread_feed.dart';

List<ThreadSummary> _items(int n) => List.generate(
      n,
      (i) => ThreadSummary(
        tid: i + 1,
        title: '帖子 $i',
        url: 'https://bbs.binmt.cc/thread-${i + 1}-1-1.html',
      ),
    );

/// 首页那种结构：上面是标题与公告，中间是吸顶的筛选条，下面是帖子。
Future<void> _pump(
  WidgetTester tester, {
  required ScrollController controller,
  VoidCallback? onTap,
  double frost = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: ThreadFeed(
            loader: (page) async => page == 1 ? _items(20) : const <ThreadSummary>[],
            controller: controller,
            header: const SizedBox(height: 500, child: Text('标题区')),
            pinnedHeader: GestureDetector(
              onTap: onTap,
              child: const SizedBox(
                height: 44,
                child: Center(child: Text('筛选条')),
              ),
            ),
            pinnedHeaderHeight: 56,
            pinnedHeaderFrost: frost,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 40),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('筛选条滚到顶部后钉住，上面的标题区正常滚走', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pump(tester, controller: controller);

    // 初始位置在标题区下面。
    expect(tester.getTopLeft(find.text('筛选条')).dy, greaterThan(400));

    controller.jumpTo(700);
    await tester.pumpAndSettle();

    // 标题区被滚出视口，筛选条贴在顶部（文字在 56 高的吸顶条里居中）。
    // 完全滚出视口后 SliverToBoxAdapter 会把内容卸载掉。
    expect(find.text('标题区'), findsNothing);
    expect(find.text('筛选条'), findsOneWidget);
    final pinnedTop = tester.getTopLeft(find.text('筛选条')).dy;
    expect(pinnedTop, lessThan(56));

    // 再往下滚，位置不变——说明是钉住的，不是恰好路过。
    controller.jumpTo(1400);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('筛选条')).dy, pinnedTop);
  });

  testWidgets('滚到最底部时筛选条依然在顶部', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pump(tester, controller: controller);

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('筛选条')).dy, lessThan(56));
  });

  testWidgets('吸顶之后仍然可以点击切换', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var taps = 0;
    await _pump(tester, controller: controller, onTap: () => taps++);

    controller.jumpTo(700);
    await tester.pumpAndSettle();

    await tester.tap(find.text('筛选条'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('开启磨砂后底板会做一层高斯模糊，条本身仍然钉住', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pump(tester, controller: controller, frost: 18);

    // 底板那层磨砂：BackdropFilter 只有在 frost > 0 时才挂。
    expect(find.byType(BackdropFilter), findsOneWidget);

    controller.jumpTo(700);
    await tester.pumpAndSettle();
    expect(find.text('筛选条'), findsOneWidget);
    expect(tester.getTopLeft(find.text('筛选条')).dy, lessThan(56));
  });
}
