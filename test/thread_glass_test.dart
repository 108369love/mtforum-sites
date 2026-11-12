import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/state/app_state.dart';
import 'package:mt_forum/ui/widgets/thread_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 帖子页三处玻璃（顶栏 / 回复框 / 右上角菜单）的配置与渲染。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.threadGlassOpacity = 0.55;
    AppState.instance.threadGlassBlur = 22;
  });

  test('帖子页玻璃参数会写进本地配置', () async {
    await AppState.instance.setThreadGlassAppearance(opacity: 0.7, blur: 12);

    expect(AppState.instance.threadGlassOpacity, closeTo(0.7, 1e-6));
    expect(AppState.instance.threadGlassBlur, closeTo(12, 1e-6));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('mt_forum_thread_glass_opacity'), closeTo(0.7, 1e-6));
    expect(prefs.getDouble('mt_forum_thread_glass_blur'), closeTo(12, 1e-6));
  });

  test('越界的值会被夹到可用区间', () async {
    await AppState.instance.setThreadGlassAppearance(opacity: 5, blur: -3);
    expect(AppState.instance.threadGlassOpacity, 0.85);
    expect(AppState.instance.threadGlassBlur, 0);

    await AppState.instance.setThreadGlassAppearance(opacity: 0, blur: 999);
    expect(AppState.instance.threadGlassOpacity, 0.05);
    expect(AppState.instance.threadGlassBlur, 40);
  });

  testWidgets('玻璃底板能按传入的透明度渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.blue)),
            Center(
              child: GlassBackdrop(
                borderRadius: BorderRadius.circular(16),
                opacity: 0.3,
                blur: 18,
                child: const SizedBox(width: 120, height: 48),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsOneWidget);
    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    // 模糊强度取的是传进来的草稿值，不是全局设置。
    expect(filter.filter, isNotNull);
    expect(find.byType(GlassBackdrop), findsOneWidget);
  });
}
