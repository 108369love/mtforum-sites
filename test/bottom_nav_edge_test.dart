import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/state/app_state.dart';
import 'package:mt_forum/ui/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 悬浮底栏的描边必须是一条连续、均匀的线。
///
/// 早先描边画在 `decoration` 里（背景层），顶部那条白色高光正好压在它上面，
/// 浅色模式下把顶边中间一段洗成和背景一样的白，看着就像线断了；再叠上
/// 半透明描边在不同底色上深浅不一，整条边「不是一条线」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.floatingGlassNav = true;
  });

  tearDown(() {
    AppState.instance.floatingGlassNav = false;
    AppState.instance.floatingNavHeight = 0;
  });

  testWidgets('描边画在内容之上，不会被高光洗白', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: AppShell()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final edge = find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final fg = w.foregroundDecoration;
      return fg is BoxDecoration && (fg.border?.top.width ?? 0) > 0;
    });
    expect(edge, findsOneWidget, reason: '底栏描边要画在 foregroundDecoration 上');

    final container = tester.widget<Container>(edge);
    final fg = container.foregroundDecoration! as BoxDecoration;
    expect(fg.border!.top.width, greaterThanOrEqualTo(1.2));
    // 太透明的描边叠在白卡片和浅灰背景上深浅差得很明显。
    expect(fg.border!.top.color.a, greaterThan(0.5));

    // 背景装饰里不能再画一层：两层描边错开半像素会变成「双线」。
    final bg = container.decoration as BoxDecoration?;
    expect(bg?.border, isNull);

    // 描边内侧不能再画一条高光：白色亮边贴在描边下面，浅色模式下就是
    // 「胶囊里还有一条线」。
    final glow = find.byWidgetPredicate(
      (w) => w is Positioned && w.top != null && w.left == 24 && w.right == 24,
    );
    expect(glow, findsNothing);
  });
}
