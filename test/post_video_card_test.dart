import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';
import 'package:mt_forum/ui/widgets/video_card.dart';

/// 帖子里「▍视频教程 → 点我播放」这种写法是 `<li><a>点我播放</a></li>`。
/// 列表项原先统一按行内文本渲染，视频链接于是只剩一条蓝字，点开才播。
void main() {
  const bili = 'https://www.bilibili.com/video/BV17DHu61ERG/'
      '?spm_id_from=333.1387.homepage.video_card.click&vd_source=c3dc3ea09ab112d382311343ae4432e7';

  Future<void> pumpHtml(WidgetTester tester, String html) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: PostHtmlView(html: html))),
    ));
    await tester.pump();
  }

  testWidgets('列表项里只有一个「点我播放」时换成播放卡片', (tester) async {
    await pumpHtml(tester, '<p>▍视频教程</p><ul><li><a href="$bili">点我播放</a></li></ul>');
    expect(find.byType(VideoCard), findsOneWidget);
  });

  testWidgets('列表项里还有别的文字时保持普通链接', (tester) async {
    await pumpHtml(tester, '<ul><li>先看这个视频 <a href="$bili">点我播放</a> 再动手</li></ul>');
    expect(find.byType(VideoCard), findsNothing);
  });

  testWidgets('普通段落里的视频链接照样是卡片', (tester) async {
    await pumpHtml(tester, '<p><a href="$bili">点我播放</a></p>');
    expect(find.byType(VideoCard), findsOneWidget);
  });

  testWidgets('不含视频的列表项仍然正常显示', (tester) async {
    await pumpHtml(tester, '<ul><li>第一条</li><li><a href="https://bbs.binmt.cc/thread-1-1-1.html">普通链接</a></li></ul>');
    expect(find.byType(VideoCard), findsNothing);
    expect(find.textContaining('第一条'), findsOneWidget);
  });
}
