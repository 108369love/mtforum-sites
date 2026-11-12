import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/state_views.dart';

/// 骨架屏：三种形态都要能画，并且不会被安全区顶下去。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, Widget child, {EdgeInsets? viewPadding}) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(padding: viewPadding ?? EdgeInsets.zero),
        child: Scaffold(body: child),
      ),
    ));
    await tester.pump();
  }

  testWidgets('卡片 / 行 / 网格三种骨架都能渲染', (tester) async {
    for (final kind in SkeletonKind.values) {
      await pump(tester, SkeletonView(kind: kind, count: 3));
      expect(find.byType(SkeletonView), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$kind 渲染不该抛异常');
    }
  });

  testWidgets('FeedSkeleton 还是帖子卡片：条数跟着 count 走', (tester) async {
    await pump(tester, const FeedSkeleton(count: 3));
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.semanticChildCount, 3);
  });

  testWidgets('topInset 把骨架推到玻璃顶栏下面', (tester) async {
    await pump(tester, const SkeletonView(kind: SkeletonKind.row, topInset: 100));
    final first = tester.getRect(find.byType(Row).first);
    expect(first.top, greaterThanOrEqualTo(100));
    expect(first.top, lessThan(140), reason: '让位就该刚好让出顶栏，不能多空一大段');
  });

  testWidgets('网格骨架不会被安全区再顶一次', (tester) async {
    // 玻璃页面开了 extendBodyBehindAppBar，MediaQuery 的顶部安全区是
    // 「状态栏 + 顶栏」；网格若不自带 padding 就会把它当内边距吃进去，
    // 版块页当初就是这么空出一大块的。
    await pump(
      tester,
      const SkeletonView(kind: SkeletonKind.grid),
      viewPadding: const EdgeInsets.only(top: 100),
    );
    final first = tester.getRect(find.byType(Column).first);
    expect(first.top, lessThan(60), reason: '安全区不能重复算进骨架的顶部内边距');
  });
}
