import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/state/app_state.dart';
import 'package:mt_forum/ui/app_shell.dart';
import 'package:mt_forum/ui/widgets/glass_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 悬浮底栏占位要和它真实占的高度对齐。
///
/// 补少了，最后一张卡片会被压进胶囊里：白色卡片和卡片外浅灰背景的分界
/// 横穿底栏，玻璃背后是白、模糊完还是白，那块看着就像没有玻璃。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.floatingGlassNav = false;
    AppState.instance.floatingNavHeight = 0;
  });

  Future<double> spaceWith(WidgetTester tester, {required double bottomInset}) async {
    late double value;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(padding: EdgeInsets.only(bottom: bottomInset)),
          child: Builder(
            builder: (context) {
              value = floatingNavSpace(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return value;
  }

  testWidgets('底栏关着的时候不占位', (tester) async {
    expect(await spaceWith(tester, bottomInset: 34), 0);
  });

  testWidgets('外壳把底栏真实高度量出来，各页面直接读', (tester) async {
    AppState.instance.floatingGlassNav = true;
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: AppShell()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 胶囊 66 + 1.2 描边占位，加上测试环境的底部安全区 0 与 minimum 10
    // 取大者。描边宽度可能微调，这里给 0.5 的容差。
    expect(AppState.instance.floatingNavHeight, closeTo(76.4, 0.5));
    // 量到之后优先用它，减 2 让最后一项略微延续到玻璃背后。
    expect(await spaceWith(tester, bottomInset: 34), closeTo(74.4, 0.5));
  });

  testWidgets('底栏开着按胶囊高度加安全区算', (tester) async {
    AppState.instance.floatingGlassNav = true;

    // 全面屏底部安全区 34：胶囊 66 + 34，再减 6 让最后一项略微延续进玻璃背后。
    expect(await spaceWith(tester, bottomInset: 34), 94);
    // 没有手势条的机型，SafeArea 的 minimum 10 顶上。
    expect(await spaceWith(tester, bottomInset: 0), 70);
  });
}
