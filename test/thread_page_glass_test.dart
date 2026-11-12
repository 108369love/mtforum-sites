import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/state/app_state.dart';
import 'package:mt_forum/ui/pages/thread_page.dart';
import 'package:mt_forum/ui/widgets/glass_app_bar.dart';
import 'package:mt_forum/ui/widgets/thread_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 帖子页布局冒烟：顶栏与回复框改成玻璃之后，不能把正文挤出屏幕。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.threadGlassOpacity = 0.55;
    AppState.instance.threadGlassBlur = 22;
  });

  testWidgets('顶栏和回复框都是玻璃，页面不溢出', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ThreadPage(tid: 1, title: '测试帖子')));
    // 网络请求在测试环境里会失败，走的是错误态，但布局照样要完整。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    // 顶栏自己不铺底色，交给 flexibleSpace 里的玻璃。
    expect(appBar.backgroundColor, Colors.transparent);
    // 顶栏现在走统一的 GlassAppBar，flexibleSpace 里是「玻璃底板 + 可选的
    // 双击回顶区」这一层，玻璃本身退到 Stack 里面。
    expect(find.byType(GlassAppBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GlassAppBar),
        matching: find.byType(GlassBackdrop),
      ),
      findsWidgets,
    );

    // 正文从顶栏背后穿过才透得出模糊，所以必须开着 extendBodyBehindAppBar。
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.extendBodyBehindAppBar, isTrue);

    // 回复框也换成了玻璃底板，且浮在正文之上。
    expect(find.byType(GlassBackdrop), findsWidgets);
  });

  testWidgets('正文层铺到回复框背后，玻璃才有东西可模糊', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ThreadPage(tid: 1, title: '测试帖子')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 回复框和正文在同一个 Stack 里，正文层必须是铺满的 _buildBody()。
    // 早先这里套了一层 Padding 给回复框让位，等于把视口截短，框后面只剩
    // Scaffold 的纯色底，模糊纯色当然一点玻璃感都没有。
    final fills = find.byWidgetPredicate(
      (w) => w is Positioned && w.left == 0 && w.top == 0 && w.right == 0 && w.bottom == 0,
    );
    expect(fills, findsOneWidget);
    final fill = tester.widget<Positioned>(fills);
    expect(fill.child, isNot(isA<Padding>()));
  });

  testWidgets('右上角菜单是自绘玻璃浮层', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ThreadPage(tid: 1, title: '测试帖子')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final before = tester.widgetList(find.byType(GlassBackdrop)).length;
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();

    // 七项菜单都出来了。
    expect(find.text('收藏主题'), findsOneWidget);
    expect(find.text('缓存帖子供离线阅读'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
    expect(find.text('在浏览器打开'), findsOneWidget);
    expect(find.text('只看楼主'), findsOneWidget);
    expect(find.text('倒序浏览'), findsOneWidget);
    expect(find.text('刷新'), findsOneWidget);

    // 多出来的一块底板就是菜单本身。
    expect(tester.widgetList(find.byType(GlassBackdrop)).length, greaterThan(before));
  });
}
