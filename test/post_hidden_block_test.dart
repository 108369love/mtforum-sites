import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';

/// Discuz 会在正文里塞一些不可见的层：附件弹层（`display:none`）、脚本、内联样式。
/// 这些内容不是正文，渲染出来就是多余的图片占位块或一大段 JS 文本，
/// 在页面上表现为「莫名其妙的空白」。
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

  testWidgets('display:none 的附件弹层不渲染，也不占位', (tester) async {
    await pumpHtml(tester, '''
      <p>正文在这里</p>
      <div class="tip aimg_tip" style="position: absolute; display: none;">
        <h4>screenshot.png</h4>
        <p><a href="forum.php?mod=attachment&amp;aid=1">下载附件</a></p>
      </div>
    ''');

    expect(find.text('正文在这里'), findsOneWidget);
    expect(find.text('下载附件'), findsNothing);
    expect(find.text('screenshot.png'), findsNothing);
  });

  testWidgets('visibility:hidden 与 hidden 属性同样跳过', (tester) async {
    await pumpHtml(tester, '''
      <p>可见段落</p>
      <div style="visibility: hidden">看不见的文字</div>
      <div hidden>也看不见</div>
    ''');

    expect(find.text('可见段落'), findsOneWidget);
    expect(find.text('看不见的文字'), findsNothing);
    expect(find.text('也看不见'), findsNothing);
  });

  testWidgets('script / style 内容不会当成正文显示', (tester) async {
    await pumpHtml(tester, '''
      <p>正常文字</p>
      <script type="text/javascript">detectPlayer("media_1", "swf", "x.swf", 600, 400);</script>
      <style type="text/css">.guestviewthumb { margin: 10px auto; }</style>
    ''');

    expect(find.text('正常文字'), findsOneWidget);
    expect(find.textContaining('detectPlayer'), findsNothing);
    expect(find.textContaining('guestviewthumb'), findsNothing);
  });
}
