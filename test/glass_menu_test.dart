import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/state/app_state.dart';
import 'package:mt_forum/ui/widgets/glass_menu.dart';
import 'package:mt_forum/ui/widgets/thread_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 玻璃菜单：能弹出、能回值、能翻边。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.threadGlassOpacity = 0.55;
    AppState.instance.threadGlassBlur = 22;
  });

  /// 造一个上下留白的页面，按钮放在 [alignment] 指定的位置。
  Widget host({
    required List<GlassMenuItem<String>> items,
    required ValueChanged<String> onSelected,
    Alignment alignment = Alignment.topRight,
    double? width,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: alignment,
          child: SizedBox(
            width: width,
            child: GlassMenuButton<String>(
              tooltip: '更多',
              items: items,
              onSelected: onSelected,
            ),
          ),
        ),
      ),
    );
  }

  const basic = [
    GlassMenuItem(value: 'copy', label: '复制楼层', icon: Icons.link_rounded),
    GlassMenuItem(value: 'report', label: '举报', icon: Icons.flag_outlined),
    GlassMenuItem(value: 'delete', label: '删除', icon: Icons.delete_outline_rounded, danger: true),
  ];

  testWidgets('点开是一块玻璃浮层，标题齐全', (tester) async {
    await tester.pumpWidget(host(items: basic, onSelected: (_) {}));
    await tester.pumpAndSettle();

    expect(find.text('复制楼层'), findsNothing);

    await tester.tap(find.byType(GlassMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('复制楼层'), findsOneWidget);
    expect(find.text('举报'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    // 底板是玻璃而不是 Material 的不透明卡片。
    expect(find.byType(GlassBackdrop), findsWidgets);
    expect(find.byType(PopupMenuItem<String>), findsNothing);
  });

  testWidgets('选中一项后回调并关闭', (tester) async {
    String? picked;
    await tester.pumpWidget(host(items: basic, onSelected: (v) => picked = v));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(GlassMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('举报'));
    await tester.pumpAndSettle();

    expect(picked, 'report');
    expect(find.text('复制楼层'), findsNothing);
  });

  testWidgets('危险项用错误色', (tester) async {
    await tester.pumpWidget(host(items: basic, onSelected: (_) {}));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GlassMenuButton<String>));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('删除'));
    final scheme = Theme.of(context).colorScheme;
    final danger = tester.widget<Text>(find.text('删除'));
    final normal = tester.widget<Text>(find.text('举报'));
    expect(danger.style!.color, scheme.error);
    expect(normal.style!.color, scheme.onSurface);
  });

  testWidgets('放不下时向上翻，菜单不出屏幕', (tester) async {
    // 按钮放在最底部：下方没有空间，菜单必须翻到上面。
    await tester.pumpWidget(
      host(items: basic, onSelected: (_) {}, alignment: Alignment.bottomRight),
    );
    await tester.pumpAndSettle();

    final button = tester.getRect(find.byType(GlassMenuButton<String>));
    await tester.tap(find.byType(GlassMenuButton<String>));
    await tester.pumpAndSettle();

    final menu = tester.getRect(find.byType(GlassBackdrop).last);
    expect(menu.bottom, lessThanOrEqualTo(button.top));
    expect(menu.top, greaterThanOrEqualTo(0));
  });

  testWidgets('贴右边缘时不会越界', (tester) async {
    await tester.pumpWidget(
      host(items: basic, onSelected: (_) {}, alignment: Alignment.topRight),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GlassMenuButton<String>));
    await tester.pumpAndSettle();

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final menu = tester.getRect(find.byType(GlassBackdrop).last);
    expect(menu.right, lessThanOrEqualTo(screen.width));
    expect(menu.left, greaterThanOrEqualTo(0));
  });

  testWidgets('点遮罩关闭，不触发回调', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(items: basic, onSelected: (_) => calls++));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GlassMenuButton<String>));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(6, 300));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.text('复制楼层'), findsNothing);
  });

  testWidgets('禁用的项点了没反应', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(
      items: const [
        GlassMenuItem(value: 'a', label: '可用', icon: Icons.check),
        GlassMenuItem(value: 'b', label: '禁用', icon: Icons.block, enabled: false),
      ],
      onSelected: (_) => calls++,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GlassMenuButton<String>));
    await tester.pumpAndSettle();

    await tester.tap(find.text('禁用'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    // 菜单还在，没被关掉。
    expect(find.text('可用'), findsOneWidget);
  });
}
