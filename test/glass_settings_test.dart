import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/state/app_state.dart';
import 'package:mt_forum/ui/pages/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.floatingGlassNav = false;
    AppState.instance.floatingGlassNavOpacity = 0.25;
    AppState.instance.floatingGlassNavBlur = 30;
    AppState.instance.composeGlassOpacity = 0.28;
    AppState.instance.composeGlassBlur = 26;
    AppState.instance.threadGlassOpacity = 0.55;
    AppState.instance.threadGlassBlur = 22;
  });

  testWidgets('「液态玻璃」一个入口同时管底栏、发帖按钮和顶栏', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
    await tester.pumpAndSettle();

    // 原来这里是「底栏液态玻璃悬浮」「发帖按钮液态玻璃」两行，现在只剩一行。
    expect(find.text('底栏液态玻璃悬浮'), findsNothing);
    expect(find.text('发帖按钮液态玻璃'), findsNothing);

    await tester.scrollUntilVisible(find.text('液态玻璃'), 260);
    await tester.pumpAndSettle();
    expect(find.text('液态玻璃'), findsOneWidget);

    await tester.tap(find.text('液态玻璃'));
    await tester.pumpAndSettle();

    // 面板里两节都在，调节项一个没少。
    expect(find.text('底部导航栏'), findsOneWidget);
    expect(find.text('发帖按钮'), findsOneWidget);
    expect(find.text('顶栏与输入条'), findsOneWidget);
    expect(find.text('启用液态玻璃悬浮底栏'), findsOneWidget);
    expect(find.text('玻璃透明度'), findsNWidgets(3));
    expect(find.text('背景模糊度'), findsNWidgets(3));
    expect(find.text('发帖按钮恢复默认'), findsOneWidget);
    expect(find.text('恢复默认'), findsOneWidget);
  });

  testWidgets('面板里改底栏参数只写底栏，发帖按钮不受影响', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('液态玻璃'), 260);
    await tester.pumpAndSettle();
    await tester.tap(find.text('液态玻璃'));
    await tester.pumpAndSettle();

    // 打开底栏的启用开关，再把第一个透明度滑杆拖到最右。
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).first, const Offset(400, 0));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('保存设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();

    expect(AppState.instance.floatingGlassNav, isTrue);
    expect(AppState.instance.floatingGlassNavOpacity, greaterThan(0.6));
    // 发帖按钮还是原来那套值。
    expect(AppState.instance.composeGlassOpacity, closeTo(0.28, 0.001));
    expect(AppState.instance.composeGlassBlur, closeTo(26, 0.001));
    // 顶栏那节也没被带着改。
    expect(AppState.instance.threadGlassOpacity, closeTo(0.55, 0.001));
    expect(AppState.instance.threadGlassBlur, closeTo(22, 0.001));
  });

  testWidgets('顶栏那节单独写自己的参数', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('液态玻璃'), 260);
    await tester.pumpAndSettle();
    await tester.tap(find.text('液态玻璃'));
    await tester.pumpAndSettle();

    // 第三节的两条滑杆是面板里最后两条：透明度、模糊度。
    final sliders = find.byType(Slider);
    expect(sliders, findsNWidgets(6));
    await tester.ensureVisible(sliders.at(4));
    await tester.pumpAndSettle();
    await tester.drag(sliders.at(4), const Offset(-400, 0));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('保存设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();

    expect(AppState.instance.threadGlassOpacity, lessThan(0.2));
    // 另外两处不受影响。
    expect(AppState.instance.floatingGlassNavOpacity, closeTo(0.25, 0.001));
    expect(AppState.instance.composeGlassOpacity, closeTo(0.28, 0.001));
  });
}
