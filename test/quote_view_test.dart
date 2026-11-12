import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';

/// 引用块要按网页端 .quote 的样子呈现：左侧灰竖线 + 浅灰底，
/// 头部「作者 发表于 时间」里的作者可点，正文完整显示、不折叠。
void main() {
  Future<void> pump(WidgetTester tester, String html) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: PostHtmlView(html: html))),
    ));
    await tester.pump();
  }

  /// 引用正文的 Text：完整显示，不应有行数限制。
  Text bodyOf(WidgetTester tester, String text) {
    final widget = tester.widget<Text>(find.text(text));
    expect(widget.maxLines, isNull);
    expect(widget.style?.decoration, isNot(TextDecoration.underline));
    return widget;
  }

  testWidgets('div.quote 渲染成引用块，作者名可点、正文不折叠', (tester) async {
    await pump(tester, '''
<div class="quote"><font size="2"><a href="home.php?mod=space&amp;uid=101">Cynnue</a> 发表于 9 分钟前</font><br />
话说这个布局一些图标怎么跟我之前开源的这么像</div>
<p>布局是让 ai 搞的，软件那么多相似点不很正常么</p>
''');

    final author = tester.widget<Text>(find.text('Cynnue'));
    expect(author.style?.color, isNotNull);
    expect(find.textContaining('发表于'), findsWidgets);
    bodyOf(tester, '话说这个布局一些图标怎么跟我之前开源的这么像');
    expect(find.text('布局是让 ai 搞的，软件那么多相似点不很正常么'), findsOneWidget);
  });

  testWidgets('标准 blockquote 与 div.quote 表现一致', (tester) async {
    await pump(tester, '''
<blockquote><font size="2"><a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=1&amp;ptid=2">网暴真的太可怕了</a> 发表于 2026-10-29 00:57</font><br />
你居然放弃了她？她删除你的时候一定哭了。</blockquote>
<p>我把视频私发你自己看吧</p>
''');

    expect(find.text('网暴真的太可怕了'), findsOneWidget);
    bodyOf(tester, '你居然放弃了她？她删除你的时候一定哭了。');
  });

  testWidgets('引用正文保留分段，并且不重复渲染原图', (tester) async {
    await pump(tester, '''
<div class="quote"><font size="2"><a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=1&amp;ptid=2">老张</a> 发表于 2026-10-29 08:00</font><br />
第一段<br />
第二段<img src="https://img.example.com/a.jpg" /></div>
<p>收到</p>
''');

    bodyOf(tester, '第一段\n第二段');
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('没有引用的楼层仍是普通段落', (tester) async {
    await pump(tester, '<p>纯正文，没有任何引用</p>');
    expect(find.text('纯正文，没有任何引用'), findsOneWidget);
  });

  testWidgets('皮肤不给 quote 类名时，靠「某某 发表于」识别引用', (tester) async {
    await pump(tester, '''
<div><font size="2"><a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=1&amp;ptid=2">老王</a> 发表于 2026-10-29 08:00</font><br />
昨天那个版本我还没试过</div>
<p>我试了，没问题</p>
''');

    expect(find.text('老王'), findsOneWidget);
    bodyOf(tester, '昨天那个版本我还没试过');
    expect(find.text('我试了，没问题'), findsOneWidget);
  });

  testWidgets('包住引用和正文的外层容器不会被误判成引用', (tester) async {
    await pump(tester, '''
<div class="comiis_message_table"><div>某某 发表于 2026-10-29 08:00<br />被引用的内容</div>
<p>我的回复</p></div>
''');

    expect(find.text('我的回复'), findsOneWidget);
    bodyOf(tester, '被引用的内容');
  });
}
