import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';

/// 站点正文大量使用 `<font color="Red">`、`color="Blue"` 这类具名色。
/// 早先把「长度 3」当成三位十六进制，`Red` 被扩展成 `RReedd` 后
/// `int.parse(radix: 16)` 抛 FormatException，整楼正文随之变成空白。
void main() {
  Future<void> pump(WidgetTester tester, String html) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: PostHtmlView(html: html))),
    ));
    await tester.pump();
  }

  /// 收集所有富文本里实际渲染出来的颜色。
  /// 正文已从「每段一个 SelectableText」改成「整楼一个 SelectionArea + Text」，
  /// 这里改为遍历底层 RichText 的 span 树。
  List<Color?> renderedColors(WidgetTester tester) {
    final colors = <Color?>[];
    for (final element in find.byType(RichText).evaluate()) {
      final widget = element.widget as RichText;
      widget.text.visitChildren((span) {
        if (span is TextSpan && span.style?.color != null) colors.add(span.style!.color);
        return true;
      });
    }
    return colors;
  }

  testWidgets('具名色 Red / Blue 不再让整楼正文空白', (tester) async {
    await pump(tester, '''
      <div class="comiis_a">
        <strong><font color="Red">一、初探</font></strong><br/>
        正文第一段，必须渲染出来。<br/>
        <font color="Blue">开篇声明</font> 后面还有内容。
      </div>
    ''');

    expect(find.textContaining('正文第一段', findRichText: true), findsWidgets);
    expect(find.textContaining('开篇声明', findRichText: true), findsWidgets);
    expect(find.textContaining('一、初探', findRichText: true), findsWidgets);

    final colors = renderedColors(tester);
    expect(colors.contains(Colors.red), isTrue, reason: 'Red 应映射到红色');
    expect(colors.contains(Colors.blue), isTrue, reason: 'Blue 应映射到蓝色');
  });

  testWidgets('十六进制与非法色值都按预期处理', (tester) async {
    await pump(tester, '''
      <font color="#ff0000">红</font>
      <font color="#0f0">绿</font>
      <font color="zzz">非法</font>
      <font color="">空</font>
    ''');

    expect(find.textContaining('红', findRichText: true), findsWidgets);
    expect(find.textContaining('非法', findRichText: true), findsWidgets);
    final colors = renderedColors(tester);
    expect(colors.contains(const Color(0xFFFF0000)), isTrue);
    expect(colors.contains(const Color(0xFF00FF00)), isTrue);
  });

  testWidgets('渲染异常时降级为纯文本而不是空白', (tester) async {
    // 故意喂一段结构怪异的内容，确认兜底分支不会把文字吞掉。
    await pump(tester, '<div><font color="Red">兜底文字</font><table><tr><td>单元格</td></tr></table></div>');
    expect(find.textContaining('兜底文字', findRichText: true), findsWidgets);
  });
}
