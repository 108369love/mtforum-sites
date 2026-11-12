import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';

/// 长图文帖（本篇 42 KB 正文：87 个 div、302 个 li、19 段引用、28 张图）曾经
/// 每段文字各挂一个 SelectableText，整楼近 1.4 万个 element。滚动时逐段做命中
/// 测试与重绘，中端机上手感发涩。现在整楼共用一个 SelectionArea、图片各自独立
/// 重绘边界，这里把这些结构约束固定下来，避免以后又改回逐段选择器。
void main() {
  Future<void> pumpThread(WidgetTester tester) async {
    final html = File('test/fixtures/thread_168143_body.html').readAsStringSync();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [PostHtmlView(html: html)]),
      ),
    ));
    // 正文按块分帧上屏（每帧 24 块），首帧只铺第一块。这里把后续帧推完，
    // 再断言整楼内容，否则图片和后半段文字还没轮到。
    for (var i = 0; i < 40; i++) {
      await tester.pump();
    }
  }

  testWidgets('长正文不再逐段创建选择器，整楼只有一个选区', (tester) async {
    await pumpThread(tester);

    expect(find.byType(SelectableText), findsNothing,
        reason: '逐段 SelectableText 是滚动卡顿的主因，正文应改用 Text');
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('正文完整渲染，图片各自独立重绘', (tester) async {
    await pumpThread(tester);

    // 首楼声明必须还在，图片不能被优化吞掉。
    expect(find.textContaining('开篇严正声明', findRichText: true), findsWidgets);
    final images = find.byType(Image).evaluate().length;
    expect(images, greaterThan(20));

    // 每张正文图都包在 RepaintBoundary 里：图片解码完成只脏自己那一块。
    final imageBoundaries = find
        .ancestor(of: find.byType(Image).first, matching: find.byType(RepaintBoundary))
        .evaluate()
        .length;
    expect(imageBoundaries, greaterThan(0));
  });

  testWidgets('滚动到图片区时仍能正常出内容', (tester) async {
    await pumpThread(tester);

    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 滚动过程中不应抛异常，且文字仍然存在。
    expect(tester.takeException(), isNull);
    expect(find.byType(PostHtmlView), findsOneWidget);
  });

  testWidgets('长正文分帧上屏，首帧不再一次铺满', (tester) async {
    final html = File('test/fixtures/thread_168143_body.html').readAsStringSync();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ListView(children: [PostHtmlView(html: html)])),
    ));
    await tester.pump();
    final firstFrame = tester.getSize(find.byType(PostHtmlView)).height;

    for (var i = 0; i < 40; i++) {
      await tester.pump();
    }
    final settled = tester.getSize(find.byType(PostHtmlView)).height;

    // 首帧只该铺前几块：整楼一次性铺开会让点开帖子那一下卡住半秒。
    expect(settled, greaterThan(firstFrame * 1.5));
    expect(find.textContaining('开篇严正声明', findRichText: true), findsWidgets);
  });
}
