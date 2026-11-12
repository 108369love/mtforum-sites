import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';

/// 正文里的纯文本地址要能被点开，尤其是隐藏内容里用户手打的裸域名。
void main() {
  Future<void> pumpHtml(WidgetTester tester, String html) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: PostHtmlView(html: html))),
    ));
    await tester.pump();
  }

  bool hasLink(WidgetTester tester, String text) {
    var found = false;
    void walk(InlineSpan span) {
      if (found) return;
      if (span is TextSpan) {
        if (span.text == text && span.recognizer != null) {
          found = true;
          return;
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          walk(child);
        }
      }
    }

    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      walk(rich.text);
      if (found) return true;
    }
    return false;
  }

  testWidgets('www 开头的裸域名也变成链接', (tester) async {
    await pumpHtml(tester, '<p>官网是 www.binmt.cc 记得收藏</p>');
    expect(hasLink(tester, 'www.binmt.cc'), isTrue);
  });

  testWidgets('隐藏内容里不带协议头的域名同样可点', (tester) async {
    // Discuz 的 hide 块里常常是这种手打地址，服务端不会加 <a>。
    await pumpHtml(tester, '''
      <div class="showhide">
        <h4>以下内容需要回复才能看到</h4>
        <p>链接：pan.baidu.com/s/1AbCdEf</p>
      </div>
    ''');
    expect(hasLink(tester, 'pan.baidu.com/s/1AbCdEf'), isTrue);
  });

  testWidgets('邮箱不会被拆成链接', (tester) async {
    await pumpHtml(tester, '<p>有问题发邮件到 help@binmt.cc 联系</p>');
    expect(hasLink(tester, 'help@binmt.cc'), isFalse);
  });

  testWidgets('版本号不会被误认成域名', (tester) async {
    await pumpHtml(tester, '<p>当前版本 1.9.5，下一个版本 1.9.6</p>');
    expect(find.textContaining('1.9.5'), findsOneWidget);
    expect(hasLink(tester, '1.9.5'), isFalse);
  });

  testWidgets('链接后面紧跟中文时，中文留正文', (tester) async {
    await pumpHtml(tester, '<p>看https://bbs.binmt.cc/thread-1-1-1.html这个帖子</p>');
    expect(hasLink(tester, 'https://bbs.binmt.cc/thread-1-1-1.html'), isTrue);
    expect(find.textContaining('这个帖子'), findsOneWidget);
  });
}
