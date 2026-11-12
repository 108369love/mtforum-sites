import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/models.dart';
import 'package:mt_forum/ui/widgets/thread_feed.dart';

/// 列表顶部的顶栏留白。
///
/// 「我的主题 / 我的回复 / 我的收藏」和标签下的帖子列表都没有 header，留白
/// 只能由列表自己撑。早先 [ThreadFeed] 只把 padding.top 给了 header 那块
/// SliverToBoxAdapter，没有 header 时 SliverPadding 的 top 恒为 0，第一条
/// 帖子直接顶到玻璃顶栏背后，头像和用户名被糊掉半行。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pagePadding = EdgeInsets.fromLTRB(14, 120, 14, 24);

  Widget host({Widget? header}) {
    return MaterialApp(
      home: Scaffold(
        body: ThreadFeed(
          loader: (_) async => <ThreadSummary>[],
          emptyText: '还没有帖子',
          padding: pagePadding,
          header: header,
        ),
      ),
    );
  }

  EdgeInsetsGeometry? listTopPadding(WidgetTester tester) {
    final finder = find.byType(SliverPadding);
    if (finder.evaluate().isEmpty) return null;
    return tester.widget<SliverPadding>(finder.first).padding;
  }

  testWidgets('没有 header 时，列表自己留出顶栏高度', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    expect(
      listTopPadding(tester)?.resolve(TextDirection.ltr).top,
      120,
      reason: '第一条内容被顶栏压住，就是这里少了留白',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('有 header 时留白由 header 撑，列表不再补一次', (tester) async {
    await tester.pumpWidget(host(header: const SizedBox(height: 40)));
    await tester.pump();

    expect(listTopPadding(tester)?.resolve(TextDirection.ltr).top, 0);

    final headerSlot = tester.widget<SliverToBoxAdapter>(find.byType(SliverToBoxAdapter).first);
    final headerPadding = (headerSlot.child as Padding).padding as EdgeInsets;
    expect(headerPadding.top, 120, reason: '留白应该只出现一次，交给 header');

    await tester.pumpAndSettle();
  });
}
