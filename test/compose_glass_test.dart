import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/state/app_state.dart';
import 'package:mt_forum/ui/widgets/glass_compose_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.composeGlassOpacity = 0.28;
    AppState.instance.composeGlassBlur = 26;
  });

  testWidgets('发帖按钮渲染为玻璃材质且保留文字与图标', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        // 垫一张底图，确保 BackdropFilter 有内容可模糊。
        body: Container(color: Colors.orange),
        floatingActionButton: GlassComposeButton(onPressed: () => tapped++),
      ),
    ));
    await tester.pump();

    expect(find.text('发帖'), findsOneWidget);
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    expect(find.byType(BackdropFilter), findsWidgets);

    await tester.tap(find.text('发帖'));
    expect(tapped, 1);
  });

  testWidgets('透明度与模糊度跟随设置变化', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox.shrink(),
        floatingActionButton: GlassComposeButton(onPressed: _noop, opacity: 0.5, blur: 8),
      ),
    ));
    await tester.pump();

    final filters = tester
        .widgetList<BackdropFilter>(find.descendant(
          of: find.byType(GlassComposeButton),
          matching: find.byType(BackdropFilter),
        ))
        .toList();
    expect(filters, isNotEmpty);
    expect(filters.first.filter, ImageFilter.blur(sigmaX: 8, sigmaY: 8));
  });

  test('外观设置会持久化，并能被重新读取', () async {
    SharedPreferences.setMockInitialValues({});
    await AppState.instance.setComposeGlassAppearance(opacity: 0.42, blur: 12);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('mt_forum_compose_glass_opacity'), closeTo(0.42, 0.001));
    expect(prefs.getDouble('mt_forum_compose_glass_blur'), closeTo(12, 0.001));
    expect(AppState.instance.composeGlassOpacity, closeTo(0.42, 0.001));
    expect(AppState.instance.composeGlassBlur, closeTo(12, 0.001));
  });

  test('越界数值会被夹到安全区间', () async {
    SharedPreferences.setMockInitialValues({});
    await AppState.instance.setComposeGlassAppearance(opacity: 3, blur: 999);
    expect(AppState.instance.composeGlassOpacity, 0.75);
    expect(AppState.instance.composeGlassBlur, 40);
  });
}

void _noop() {}
