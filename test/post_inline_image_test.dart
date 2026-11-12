import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';

/// 行内元素里包着的图片不能留在段落里。
///
/// 手机模板（comiis）的附件图都是 `<span class="comiis_postimg"><img></span>`。
/// span 不是块级标签，图片曾经被塞进 `Text` 的 WidgetSpan：按整行宽度铺开、
/// 高度按原图比例算，一张 1080×4252 的截图会给这一段排出一千三百多像素的行高，
/// 行内文字按 middle 对齐被挤到正中间——正文里凭空多出上下好几屏空白，长按也
/// 选不中（那是图片容器，不是文字）。
void main() {
  Future<void> render(WidgetTester tester, String html) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 332,
            child: PostHtmlView(html: html, selectable: false),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  /// 段落里是不是还嵌着行内组件（图片）。
  bool hasInlineWidget(WidgetTester tester) {
    final paragraphs = find.byType(RichText).evaluate();
    for (final element in paragraphs) {
      final paragraph = element.renderObject! as RenderParagraph;
      final stack = <InlineSpan>[paragraph.text];
      while (stack.isNotEmpty) {
        final span = stack.removeLast();
        if (span is WidgetSpan) return true;
        if (span is TextSpan) stack.addAll(span.children ?? const []);
      }
    }
    return false;
  }

  testWidgets('span 包着的附件图单独成块，不再进入段落', (tester) async {
    await render(
      tester,
      '<div>这是正文的第一段文字<br>'
      '<span class="comiis_postimg vm"><img src="https://example.com/long.png"></span>'
      '<br>这是正文的第二段文字</div>',
    );

    expect(hasInlineWidget(tester), isFalse, reason: '图片应当从段落里拆出来');
    // 图片仍然要显示，只是走块级路径（加载失败时是 160 高的占位）。
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('图片两侧的文字保持各自成段，不会被同一行撑开', (tester) async {
    await render(
      tester,
      '<div><span class="comiis_postimg"><img src="https://example.com/a.png"></span>'
      '图片下面的说明文字</div>',
    );

    // 段落只剩说明文字，高度不该被图片占位（160）撑起来。
    final heights = find
        .byType(RichText)
        .evaluate()
        .map((e) => (e.renderObject! as RenderParagraph).size.height)
        .toList();
    expect(heights.any((h) => h > 120), isFalse, reason: '段落高度不应包含图片');
  });

  testWidgets('行内表情仍然留在段落里', (tester) async {
    await render(
      tester,
      '<div>好的<img src="https://bbs.binmt.cc/static/image/smiley/default/smile.gif">收到</div>',
    );

    expect(hasInlineWidget(tester), isTrue, reason: '表情是行内元素，不该被拆成块');
  });

  testWidgets('正常行内标签不受影响', (tester) async {
    await render(tester, '<div>正文<strong>加粗</strong>继续</div>');

    expect(hasInlineWidget(tester), isFalse);
    expect(find.textContaining('加粗'), findsOneWidget);
  });
}
