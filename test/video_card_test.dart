import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';
import 'package:mt_forum/ui/pages/video_player_page.dart';
import 'package:mt_forum/ui/widgets/inline_video_player.dart';
import 'package:mt_forum/ui/widgets/video_card.dart';

/// 正文里的视频链接应当渲染成一块可点击的播放区域，
/// 而不是一条需要跳浏览器才能看的普通链接。
void main() {
  Future<void> pump(WidgetTester tester, String html) async {
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

  testWidgets('单独成段的 B站链接变成播放卡片', (tester) async {
    await pump(tester, '''
      <div class="comiis_a">
        视频演示：https://www.bilibili.com/video/BV1xx411c7mD
        <br/>
        后面还有正文。
      </div>
    ''');

    expect(find.byType(VideoCard), findsOneWidget);
    expect(find.text('哔哩哔哩'), findsOneWidget);
    expect(find.text('视频演示'), findsWidgets);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('嵌入的 iframe 播放器也走播放卡片', (tester) async {
    await pump(tester, '''
      <div class="media">
        <iframe src="//player.bilibili.com/player.html?bvid=BV1xx411c7mD&autoplay=0&danmaku=0"></iframe>
      </div>
    ''');

    expect(find.byType(VideoCard), findsOneWidget);
    expect(find.text('BV1xx411c7mD'), findsOneWidget);
  });

  testWidgets('句子中间的链接保留为行内文字，不抢占正文', (tester) async {
    await pump(tester, '''
      <div>这次更新改动很多，演示放在 https://www.bilibili.com/video/BV1xx411c7mD 里，可以看看。</div>
    ''');

    expect(find.byType(VideoCard), findsNothing);
    expect(find.textContaining('这次更新改动很多', findRichText: true), findsWidgets);
  });

  testWidgets('普通外链不会被当成视频', (tester) async {
    await pump(tester, '<div>下载：https://pan.quark.cn/s/abcdef</div>');
    expect(find.byType(VideoCard), findsNothing);
    expect(find.textContaining('pan.quark.cn', findRichText: true), findsWidgets);
  });

  // 线上帖子的真实写法：正文里一行说明 + 一个「视频演示」文字链接指向 mp4。
  testWidgets('文字是「视频演示」的直链 mp4 也变成播放区域', (tester) async {
    await pump(tester, '''
      <div class="comiis_a">
        对，就是这样，如果你想看一下成果视频的话，链接如下<br/>
        <a href="https://oss.crash.fan/video/Video_1793383126518_230.mp4" target="_blank">视频演示</a><br/>
        感谢感谢
      </div>
    ''');

    expect(find.byType(VideoCard), findsOneWidget);
    expect(find.textContaining('点击在应用内播放'), findsOneWidget);
    expect(find.text('视频演示'), findsWidgets);
    expect(find.textContaining('感谢感谢', findRichText: true), findsWidgets);
  });

  // 用户要的是「点一下就播」，而不是跳到另一个页面。
  testWidgets('点击播放区域就地展开播放器，页面不跳转', (tester) async {
    await pump(tester, '''
      <div class="comiis_a">
        链接如下<br/>
        <a href="https://oss.crash.fan/video/Video_1793383126518_230.mp4">视频演示</a>
      </div>
    ''');

    expect(find.byType(InlineVideoPlayer), findsNothing);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    expect(find.byType(InlineVideoPlayer), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
    expect(find.text('正在正文中播放'), findsOneWidget);
    // 仍在帖子正文里，没有 push 播放页
    expect(find.byType(PostHtmlView), findsOneWidget);
    expect(find.byType(VideoPlayerPage), findsNothing);

    await tester.tap(find.text('收起'));
    await tester.pump();
    expect(find.byType(InlineVideoPlayer), findsNothing);
  });
}
