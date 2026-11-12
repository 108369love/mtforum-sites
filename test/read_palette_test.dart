import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/state/app_state.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';
import 'package:mt_forum/ui/widgets/read_palette_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阅读配色：正文里的链接、「回复可见」提示都能单独设色。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.readLinkColor = null;
    AppState.instance.readHintColor = null;
  });

  Widget host(String html) => MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PostHtmlView(html: html, selectable: false),
          ),
        ),
      );

  /// 找到正文里某段文字所在的 span。
  TextSpan? spanOf(WidgetTester tester, String text) {
    for (final element in find.byType(RichText).evaluate()) {
      final rich = element.widget as RichText;
      TextSpan? hit;
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == text) hit = span;
        return hit == null;
      });
      if (hit != null) return hit;
    }
    return null;
  }

  testWidgets('链接默认跟主题色，设了颜色就走设的', (tester) async {
    await tester.pumpWidget(host('<p>下载：<a href="https://example.com/a.zip">点这里</a></p>'));
    await tester.pumpAndSettle();

    final scheme = Theme.of(tester.element(find.byType(PostHtmlView))).colorScheme;
    expect(spanOf(tester, '点这里')?.style?.color, scheme.primary);

    const chosen = Color(0xFFDC2626);
    await AppState.instance.setReadLinkColor(chosen);
    await tester.pump();

    expect(spanOf(tester, '点这里')?.style?.color, chosen);
    expect(spanOf(tester, '点这里')?.style?.decoration, TextDecoration.underline);
  });

  testWidgets('裸链接也吃同一套颜色', (tester) async {
    AppState.instance.readLinkColor = const Color(0xFF0891B2);
    await tester.pumpWidget(host('<p>网盘 pan.baidu.com/s/abc123 自取</p>'));
    await tester.pumpAndSettle();

    expect(spanOf(tester, 'pan.baidu.com/s/abc123')?.style?.color, const Color(0xFF0891B2));
  });

  testWidgets('「回复可见」提示整行加粗并使用提示色', (tester) async {
    AppState.instance.readHintColor = const Color(0xFF7C3AED);
    await tester.pumpWidget(host('<p>正文第一段</p><p>本帖隐藏内容需要回复才能查看</p>'));
    await tester.pumpAndSettle();

    final hint = spanOf(tester, '本帖隐藏内容需要回复才能查看');
    expect(hint?.style?.color, const Color(0xFF7C3AED));
    expect(hint?.style?.fontWeight, FontWeight.w600);

    // 普通正文不能被染色。
    final body = spanOf(tester, '正文第一段');
    expect(body?.style?.color, isNot(const Color(0xFF7C3AED)));
    expect(body?.style?.fontWeight, isNot(FontWeight.w600));
  });

  testWidgets('正文里随口提到「回复」不会被染成提示色', (tester) async {
    // 站内真实回帖：请求把「回复」和链接分开配色，句子本身不是提示。
    await tester.pumpWidget(host(
      '<p>能申请添加一下颜色调节吗？，把需要回复和链接改个颜色吗，不好识别</p>'
      '<p>且建议增加帖子隐藏内容中检测链接并自动标记为超文本链接</p>'
      '<p>帖子里面，的隐藏贴，回复才能看，但是app渲染的背景都一样</p>',
    ));
    await tester.pumpAndSettle();

    final hintColor = AppState.instance.readHintColorOf(
      Theme.of(tester.element(find.byType(PostHtmlView))).colorScheme,
    );
    for (final line in <String>[
      '能申请添加一下颜色调节吗？，把需要回复和链接改个颜色吗，不好识别',
      '且建议增加帖子隐藏内容中检测链接并自动标记为超文本链接',
      '帖子里面，的隐藏贴，回复才能看，但是app渲染的背景都一样',
    ]) {
      expect(spanOf(tester, line)?.style?.color, isNot(hintColor), reason: line);
      expect(spanOf(tester, line)?.style?.fontWeight, isNot(FontWeight.w600), reason: line);
    }
  });

  testWidgets('真正的提示照样染色：段首提示与句尾「回复可见」', (tester) async {
    await tester.pumpWidget(host(
      '<p>本帖隐藏内容需要回复才能查看</p>'
      '<p>下载地址回复可见</p>',
    ));
    await tester.pumpAndSettle();

    final hintColor = AppState.instance.readHintColorOf(
      Theme.of(tester.element(find.byType(PostHtmlView))).colorScheme,
    );
    expect(spanOf(tester, '本帖隐藏内容需要回复才能查看')?.style?.color, hintColor);
    expect(spanOf(tester, '下载地址回复可见')?.style?.color, hintColor);
  });

  testWidgets('配色弹层改色会立刻生效', (tester) async {
    // 真机宽度下量一遍，色板换行或长文案挤爆都会在这里抛 overflow。
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showReadPaletteSheet(context),
              child: const Text('打开配色'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开配色'));
    await tester.pumpAndSettle();

    expect(find.text('阅读配色'), findsOneWidget);
    expect(find.text('链接颜色'), findsOneWidget);
    expect(find.text('回复提示颜色'), findsOneWidget);

    // 「朱红」在两组色板里都有，第一个是链接那一组。
    await tester.tap(find.text('朱红').first);
    await tester.pumpAndSettle();

    expect(AppState.instance.readLinkColor?.toARGB32(), 0xFFDC2626);
    expect(AppState.instance.readHintColor, isNull, reason: '改链接色不该动到提示色');
    expect(tester.takeException(), isNull, reason: '390 宽下弹层不该溢出');
  });

  test('颜色会落盘，恢复默认时把键删掉', () async {
    await AppState.instance.setReadLinkColor(const Color(0xFFDC2626));
    await AppState.instance.setReadHintColor(const Color(0xFF16A34A));

    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('mt_forum_read_link_color'), 0xFFDC2626);
    expect(prefs.getInt('mt_forum_read_hint_color'), 0xFF16A34A);

    await AppState.instance.setReadLinkColor(null);
    await AppState.instance.setReadHintColor(null);

    prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('mt_forum_read_link_color'), isFalse);
    expect(prefs.containsKey('mt_forum_read_hint_color'), isFalse);

    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF607080));
    expect(AppState.instance.readLinkColorOf(scheme), scheme.primary);
    expect(AppState.instance.readHintColorOf(scheme), const Color(0xFFD2691E));
  });
}
