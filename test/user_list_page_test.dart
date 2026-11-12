import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/http_session.dart';
import 'package:mt_forum/data/models.dart';
import 'package:mt_forum/ui/pages/user_list_page.dart';
import 'package:mt_forum/ui/widgets/state_views.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 好友 / 粉丝 / 关注三页合一后的公共行为。
///
/// 这三个页面原来各写一遍加载、分页、登录态、空态，改一处要同步三处；
/// 现在都走 [UserListPage]，测试只要盯这一个外壳就够了。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HttpSession.instance.clear();
  });

  tearDown(() {
    HttpSession.instance.clear();
  });

  /// 会话认 `*_auth` 这个 cookie；直接种一个，避免测试去跑登录流程。
  void login() => HttpSession.instance.setCookie('xx_auth', 'token');

  Future<void> pump(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  UserListPage listWith({
    required Future<List<FriendItem>> Function(int page) loader,
    String emptyText = '还没有粉丝',
    bool paged = true,
    List<Widget> Function(BuildContext, FriendItem, UserListHandle)? actions,
  }) {
    return UserListPage(
      title: '我的粉丝',
      loader: loader,
      emptyText: emptyText,
      loginHint: '登录后查看我的粉丝',
      loginIcon: Icons.people_outline_rounded,
      subtitle: userCountsSubtitle,
      paged: paged,
      actions: actions,
    );
  }

  testWidgets('没登录时给登录入口，不去请求接口', (tester) async {
    var called = false;
    await pump(tester, listWith(loader: (_) async {
      called = true;
      return const [];
    }));

    expect(find.text('登录后查看我的粉丝'), findsOneWidget);
    expect(find.text('立即登录'), findsOneWidget);
    expect(called, isFalse, reason: '没登录不该白跑一次请求');
  });

  testWidgets('空列表给 EmptyView，而不是一片空白', (tester) async {
    login();
    await pump(tester, listWith(loader: (_) async => const []));

    expect(find.byType(EmptyView), findsOneWidget);
    expect(find.text('还没有粉丝'), findsOneWidget);
  });

  testWidgets('有数据时按行渲染，副标题是关注/粉丝数', (tester) async {
    login();
    await pump(tester, listWith(loader: (_) async => const [
          FriendItem(uid: 1, username: '张三', followers: 8, following: 3),
          FriendItem(uid: 2, username: '李四'),
        ]));

    expect(find.text('张三'), findsOneWidget);
    expect(find.text('关注 3  ·  粉丝 8'), findsOneWidget);
    expect(find.text('UID 2'), findsOneWidget, reason: '两个计数都是 0 时退回 UID');
  });

  testWidgets('加载失败给错误页，点重试能恢复', (tester) async {
    login();
    var attempts = 0;
    await pump(tester, listWith(loader: (_) async {
      attempts++;
      if (attempts == 1) throw SiteException('网络异常');
      return const [FriendItem(uid: 9, username: '王五')];
    }));

    expect(find.text('网络异常'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('王五'), findsOneWidget);
  });

  testWidgets('分页：滚到底追加下一页，重复数据不重复渲染', (tester) async {
    login();
    final requested = <int>[];
    await pump(tester, listWith(loader: (page) async {
      requested.add(page);
      if (page == 1) {
        return [for (var i = 0; i < 12; i++) FriendItem(uid: i, username: '用户$i')];
      }
      return [for (var i = 10; i < 20; i++) FriendItem(uid: i, username: '用户$i')];
    }));

    expect(requested, [1]);
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(requested.take(2), [1, 2], reason: '滚到底要接着请求下一页');

    // 第二页把 10、11 又返回了一次。再滚一次时全是重复数据，应当就此停住，
    // 不能一直翻下去（站点到最后一页常常会重复返回同一页）。
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(requested.length, lessThanOrEqualTo(3));
    expect(requested.toSet().length, requested.length, reason: '同一页不该请求两次');
  });

  testWidgets('paged=false 的列表滚到底也不再请求', (tester) async {
    login();
    final requested = <int>[];
    await pump(tester, listWith(paged: false, loader: (page) async {
      requested.add(page);
      return [for (var i = 0; i < 12; i++) FriendItem(uid: i, username: '好友$i')];
    }));

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(requested, [1]);
  });

  testWidgets('actions 给什么就渲染什么，没给就只显示箭头', (tester) async {
    login();
    await pump(tester, listWith(
      loader: (_) async => const [FriendItem(uid: 1, username: '张三')],
      actions: (_, __, ___) => [
        IconButton(onPressed: () {}, icon: const Icon(Icons.edit_note_rounded)),
        IconButton(onPressed: () {}, icon: const Icon(Icons.star_outline_rounded)),
      ],
    ));
    expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
    expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

    await pump(tester, listWith(loader: (_) async => const [FriendItem(uid: 1, username: '张三')]));
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('顶栏是玻璃，标题跟着页面走', (tester) async {
    login();
    await pump(tester, listWith(loader: (_) async => const []));
    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.backgroundColor, Colors.transparent);
    expect(find.text('我的粉丝'), findsOneWidget);
  });

  testWidgets('订阅副标题：只有关注数时不出现「粉丝 0」', (tester) async {
    expect(
      userCountsSubtitle(const FriendItem(uid: 1, username: 'a', following: 6)),
      '关注 6',
    );
    expect(
      userCountsSubtitle(const FriendItem(uid: 1, username: 'a')),
      'UID 1',
    );
  });
}
