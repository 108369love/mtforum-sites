import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/app_theme.dart';

/// 页面转场：不能有「白底遮罩 + 新页淡入」的那一套。
///
/// Android 默认的 PredictiveBack / Zoom 转场会在退场时把旧页缩成圆角卡片并
/// 垫一层 surface 遮罩，入场再把新页从 0.85 缩放到 1 并淡入。转场半程整屏
/// 发白，前后两页同时半透明地叠在一起——浅色主题看着像糊了一层毛玻璃。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host({ThemeData? theme}) {
    return MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: Text('第二页')),
                  ),
                ),
              ),
              child: const Text('去第二页'),
            ),
          ),
        ),
      ),
    );
  }

  /// push 之后停在转场半程，数一数第二页身上挂了几层 `FadeTransition`。
  ///
  /// Zoom 转场的入口页是 `FadeTransition(screen) → ScaleTransition(page)`，
  /// 所以这里必然大于 0；Cupertino 转场只有位移和阴影，恒为 0。
  Future<int> fadeLayersAtMidTransition(WidgetTester tester, Widget app) async {
    await tester.pumpWidget(app);
    await tester.tap(find.text('去第二页'));
    await tester.pump(); // 让 push 生效，动画从 0 开始
    await tester.pump(const Duration(milliseconds: 90)); // 转场半程
    final count = find
        .ancestor(of: find.text('第二页'), matching: find.byType(FadeTransition))
        .evaluate()
        .length;
    await tester.pumpAndSettle();
    return count;
  }

  testWidgets('转场半程新页不淡入，切页不会整屏发白', (tester) async {
    expect(await fadeLayersAtMidTransition(tester, host()), 0);
  });

  testWidgets('对照组：Material 默认转场确实会淡入，说明上面的断言抓得住问题', (tester) async {
    expect(
      await fadeLayersAtMidTransition(tester, host(theme: ThemeData())),
      greaterThan(0),
    );
  });

  test('浅色和深色主题的所有平台都注册了横向转场', () {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      for (final platform in TargetPlatform.values) {
        expect(
          theme.pageTransitionsTheme.builders[platform],
          isA<CupertinoPageTransitionsBuilder>(),
          reason: '${platform.name} 还在用默认转场，切页会白屏、叠影',
        );
      }
    }
  });
}
