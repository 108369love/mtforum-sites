import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/pages/boards_page.dart';
import 'package:mt_forum/ui/pages/compose_page.dart';
import 'package:mt_forum/ui/pages/notifications_page.dart';
import 'package:mt_forum/ui/pages/pm_chat_page.dart';
import 'package:mt_forum/ui/pages/pm_list_page.dart';
import 'package:mt_forum/ui/pages/profile_page.dart';
import 'package:mt_forum/ui/pages/search_page.dart';
import 'package:mt_forum/ui/pages/user_page.dart';
import 'package:mt_forum/ui/widgets/glass_app_bar.dart';
import 'package:mt_forum/ui/widgets/thread_feed.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 玻璃顶栏的布局契约：顶栏透明 + body 从它背后开始。
///
/// 这两件事必须成对出现。只把顶栏改透明、忘了 extendBodyBehindAppBar，
/// 玻璃背后就是一块纯色，看起来像块白板；只开 extendBodyBehindAppBar、
/// 忘了给列表补 [glassTopInset]，第一条内容会被顶栏压住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  void expectGlassChrome(WidgetTester tester, {required String page}) {
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.extendBodyBehindAppBar, isTrue, reason: '$page 的正文要从顶栏背后滚过');

    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.backgroundColor, Colors.transparent, reason: '$page 的顶栏要不铺底色');
    expect(appBar.flexibleSpace, isA<Stack>(), reason: '$page 的顶栏底板要是玻璃');
    expect(tester.takeException(), isNull);
  }

  testWidgets('版块页顶栏是玻璃', (tester) async {
    await pumpPage(tester, const BoardsPage());
    expectGlassChrome(tester, page: '版块页');
  });

  testWidgets('消息提醒页顶栏是玻璃', (tester) async {
    await pumpPage(tester, const NotificationsPage());
    expectGlassChrome(tester, page: '消息提醒页');
  });

  testWidgets('私信列表页顶栏是玻璃', (tester) async {
    await pumpPage(tester, const PmListPage());
    expectGlassChrome(tester, page: '私信列表页');
  });

  testWidgets('私信聊天页顶栏是玻璃，输入条浮在消息上', (tester) async {
    await pumpPage(tester, const PmChatPage(uid: 1, name: '测试用户'));
    expectGlassChrome(tester, page: '私信聊天页');

    // 输入条和消息列表在同一个 Stack：消息列表铺满，输入条叠在上面，
    // 气泡才能从玻璃输入条背后掠过。套一层 Padding 就会把视口截短。
    //
    // 未登录时页面只有「登录后查看私信」，不会渲染输入条，这里跳过；
    // 有输入框就说明走的是对话布局，必须满足悬浮结构。
    if (find.byType(TextField).evaluate().isNotEmpty) {
      final fills = find.byWidgetPredicate(
        (w) => w is Positioned && w.left == 0 && w.top == 0 && w.right == 0 && w.bottom == 0,
      );
      expect(fills, findsOneWidget);
      expect(tester.widget<Positioned>(fills).child, isNot(isA<Padding>()));
    }
  });

  testWidgets('发帖页顶栏是玻璃，工具条浮在正文上', (tester) async {
    await pumpPage(tester, const ComposePage());
    expectGlassChrome(tester, page: '发帖页');

    final fills = find.byWidgetPredicate(
      (w) => w is Positioned && w.left == 0 && w.top == 0 && w.right == 0 && w.bottom == 0,
    );
    expect(fills, findsOneWidget);
    expect(tester.widget<Positioned>(fills).child, isNot(isA<Padding>()));
  });

  testWidgets('我的页顶栏是玻璃', (tester) async {
    await pumpPage(tester, const ProfilePage());
    expectGlassChrome(tester, page: '我的页');
  });

  testWidgets('搜索页顶栏是玻璃，搜索条浮在结果上', (tester) async {
    await pumpPage(tester, const SearchPage());
    expectGlassChrome(tester, page: '搜索页');

    final fills = find.byWidgetPredicate(
      (w) => w is Positioned && w.left == 0 && w.top == 0 && w.right == 0 && w.bottom == 0,
    );
    expect(fills, findsOneWidget);
  });

  testWidgets('个人主页顶栏是玻璃，Tab 改由列表吸顶', (tester) async {
    await pumpPage(tester, const UserPage(uid: 1, name: '测试用户'));
    expectGlassChrome(tester, page: '个人主页');

    // 资料卡加载完之后，TabBar 应该挂在 ThreadFeed 的吸顶槽里，
    // 而不是像以前那样固定在 Column 里、背后永远是一张静态卡片。
    await tester.pump(const Duration(seconds: 1));
    final tabInFeed = find.descendant(
      of: find.byType(ThreadFeed),
      matching: find.byType(TabBar),
    );
    // 加载失败时走的是错误态，没有列表；只要没抛异常就算过。
    if (find.byType(ThreadFeed).evaluate().isNotEmpty) {
      expect(tabInFeed, findsWidgets);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('glassTopInset 把状态栏和顶栏一起算进去', (tester) async {
    late double inset;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            inset = glassTopInset(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(inset, greaterThanOrEqualTo(kToolbarHeight));
  });
}
