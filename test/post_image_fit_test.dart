import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';

/// 正文图片曾经被套死在 `maxHeight: 520` 里，配合 `BoxFit.fitWidth`：
/// 宽度铺满、高度超出的部分被圆角一刀裁掉。手机截图按屏宽铺开普遍 800+ 高，
/// 结果每张长图只看得到上半截。这里把「不裁」的约束固定下来。
void main() {
  Future<void> pumpWithImage(WidgetTester tester, String html) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: PostHtmlView(html: html)),
      ),
    ));
    await tester.pump();
  }

  testWidgets('正文图片按 contain 完整显示，不再被固定高度裁掉', (tester) async {
    await pumpWithImage(tester, '<div><img src="https://example.com/shot.png"></div>');

    final image = tester.widget<Image>(find.byType(Image).first);
    expect(image.fit, BoxFit.contain,
        reason: 'fitWidth 在高度受限时会把长图截断，必须用 contain 才能整体缩进框内');
    expect(image.width, double.infinity);
  });

  testWidgets('高度上限跟着屏幕走，不再是写死的 520', (tester) async {
    await pumpWithImage(tester, '<div><img src="https://example.com/shot.png"></div>');

    // 逻辑屏高 800，上限取一屏半，长截图能完整铺开。
    final boxes = tester
        .widgetList<ConstrainedBox>(find.byType(ConstrainedBox))
        .where((b) {
          final max = b.constraints.maxHeight;
          return max.isFinite && max >= 400;
        })
        .toList();
    expect(boxes, isNotEmpty);
    expect(boxes.first.constraints.maxHeight, 1280,
        reason: '800 逻辑高度 × 1.6，夹在 400–1600 之间');
  });
}
