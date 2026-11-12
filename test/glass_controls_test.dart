import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/glass_controls.dart';

/// 公共玻璃控件的契约：一个 App 里「胶囊」「搜索框」「卡片」只有一种长相。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child, {Brightness brightness = Brightness.light}) => MaterialApp(
        theme: ThemeData(brightness: brightness, colorSchemeSeed: Colors.blue),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('GlassPill 能点，返回的就是这一粒', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(GlassPill(label: '全部版块', onTap: () => taps++)));

    expect(find.text('全部版块'), findsOneWidget);
    await tester.tap(find.text('全部版块'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('GlassPill 选中态换成主色，和中性态不是同一个前景色', (tester) async {
    await tester.pumpWidget(host(
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassPill(label: '普通', onTap: _noop),
          GlassPill(label: '选中', onTap: _noop, selected: true),
        ],
      ),
    ));

    final normal = tester.widget<Text>(find.text('普通'));
    final selected = tester.widget<Text>(find.text('选中'));
    expect(selected.style!.color, isNot(normal.style!.color), reason: '选中态要用主色区分出来');
  });

  testWidgets('accent 胶囊是标签语义，直接用主色前景', (tester) async {
    await tester.pumpWidget(host(GlassPill(label: 'MT管理器', tone: GlassPillTone.accent, onTap: _noop)));
    final scheme = Theme.of(tester.element(find.text('MT管理器'))).colorScheme;
    expect(tester.widget<Text>(find.text('MT管理器')).style!.color, scheme.primary);
  });

  testWidgets('GlassSearchField 打字会回调，清除按钮能清空', (tester) async {
    final controller = TextEditingController();
    final typed = <String>[];
    await tester.pumpWidget(host(GlassSearchField(
      controller: controller,
      hintText: '搜索帖子',
      onChanged: typed.add,
    )));

    expect(find.text('搜索帖子'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '逆向');
    await tester.pump();
    expect(typed, ['逆向']);

    // 有内容时才出现清除按钮
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.cancel_rounded));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(typed.last, isEmpty);
  });

  testWidgets('GlassSearchField 聚焦时描边加粗并转主色', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(host(GlassSearchField(controller: controller)));

    BoxDecoration decoration() {
      final container = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      return container.decoration! as BoxDecoration;
    }

    final idle = decoration();
    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 200));
    final focused = decoration();

    expect(focused.border!.top.width, greaterThan(idle.border!.top.width));
    expect(focused.boxShadow, isNotNull);
  });

  testWidgets('GlassCard 铺自己的底色，水波纹才不会被挡', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(
      GlassCard(onTap: () => taps++, padding: const EdgeInsets.all(12), child: const Text('点我')),
    ));

    final material = tester.widget<Material>(find.byType(Material).last);
    expect(material.color, isNotNull);
    expect(material.color!.a, greaterThan(0), reason: '底色要由 Material 自己铺');

    await tester.tap(find.text('点我'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('深色下胶囊和卡片仍然是半透明，不是死白', (tester) async {
    await tester.pumpWidget(host(
      GlassCard(child: GlassPill(label: '深色', onTap: _noop)),
      brightness: Brightness.dark,
    ));
    final material = tester.widget<Material>(find.byType(Material).last);
    expect(material.color!.a, lessThan(0.5));
  });
}

void _noop() {}
