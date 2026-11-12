import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/pages/about_page.dart';
import 'package:mt_forum/ui/pages/black_house_page.dart';
import 'package:mt_forum/ui/pages/credit_page.dart';
import 'package:mt_forum/ui/pages/followers_page.dart';
import 'package:mt_forum/ui/pages/following_page.dart';
import 'package:mt_forum/ui/pages/friends_page.dart';
import 'package:mt_forum/ui/pages/magic_page.dart';
import 'package:mt_forum/ui/pages/mcp_page.dart';
import 'package:mt_forum/ui/pages/medals_page.dart';
import 'package:mt_forum/ui/pages/offline_cache_page.dart';
import 'package:mt_forum/ui/pages/rankings_page.dart';
import 'package:mt_forum/ui/pages/site_features_page.dart';
import 'package:mt_forum/ui/pages/site_module_page.dart';
import 'package:mt_forum/ui/pages/tags_page.dart';
import 'package:mt_forum/ui/widgets/glass_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 二级页面的玻璃顶栏契约。
///
/// 主路径早就换成了玻璃，二级页却一直是不透明白条：从版块点进排行榜、
/// 勋章、积分，顶栏会“啪”地从玻璃变白板。这批页面统一后，这里挨个盯住：
/// 顶栏透明 + body 从背后滚过 + 首条内容让出顶栏高度。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
  }

  void expectGlass(WidgetTester tester, String name) {
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.extendBodyBehindAppBar, isTrue, reason: '$name 的正文要从顶栏背后滚过');
    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.backgroundColor, Colors.transparent, reason: '$name 的顶栏不该铺底色');
    expect(appBar.flexibleSpace, isA<Stack>(), reason: '$name 的顶栏底板要是玻璃');
    expect(tester.takeException(), isNull, reason: '$name 渲染时抛异常了');
  }

  final pages = <String, Widget>{
    '关于': const AboutPage(),
    '排行榜': const RankingsPage(),
    '标签': const TagsPage(),
    '勋章中心': const MedalsPage(),
    '积分': const CreditPage(),
    '小黑屋': const BlackHousePage(),
    '更多站点功能': const SiteFeaturesPage(),
    '站点模块': const SiteModulePage(title: '测试模块', path: 'home.php?mod=spacecp'),
    '离线缓存': const OfflineCachePage(),
    '我的好友': const FriendsPage(),
    '我的粉丝': const FollowersPage(),
    '我的关注': const FollowingPage(),
    'MCP 服务': const McpPage(),
  };

  pages.forEach((name, page) {
    testWidgets('$name 顶栏是玻璃', (tester) async {
      await pump(tester, page);
      expectGlass(tester, name);
    });
  });

  testWidgets('道具中心的顶栏连 TabBar 一起算进留白', (tester) async {
    await pump(tester, const MagicPage());
    expectGlass(tester, '道具中心');

    // TabBar 挂在顶栏 bottom 上，正文的顶部留白要把这 46dp 也算进去，
    // 否则第一张卡片会被三行 Tab 压住。
    final tabBar = tester.widget<TabBar>(find.byType(TabBar).first);
    expect(tabBar, isNotNull);
    expect(glassTopInset(tester.element(find.byType(TabBar).first), bottomHeight: kTextTabBarHeight),
        greaterThanOrEqualTo(kToolbarHeight + kTextTabBarHeight));
  });

  testWidgets('glassPagePadding 把左右边距固定成 14', (tester) async {
    late EdgeInsets padding;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 40)),
          child: Builder(
            builder: (context) {
              padding = glassPagePadding(context, top: 12, bottom: 30);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(padding.left, kPageGutter);
    expect(padding.right, kPageGutter);
    expect(padding.top, 40 + kToolbarHeight + 12);
    expect(padding.bottom, 30);
  });
}
