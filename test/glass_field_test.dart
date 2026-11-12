import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/glass_controls.dart';

/// 玻璃表单控件的契约。
///
/// 登录页、发帖页原来直接用 Material 的 `InputDecoration`：底下一道下划线、
/// 聚焦时标签往边框上跳。玻璃卡片上横着一条线，看着像网页表单。这批断言
/// 锁住三件事：不再有下划线、聚焦有可见反馈、选择行点得动。
void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: Container(
            color: Colors.teal,
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      );

  InputDecoration decorationOf(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).decoration!;

  testWidgets('GlassField 没有主题自带的下划线', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(wrap(GlassField(controller: controller, hintText: '请输入用户名')));

    final decoration = decorationOf(tester);
    expect(decoration.border, InputBorder.none);
    expect(decoration.enabledBorder, InputBorder.none);
    expect(decoration.focusedBorder, InputBorder.none);
    expect(decoration.counterText, '');
    expect(find.text('请输入用户名'), findsOneWidget);
  });

  testWidgets('label 常驻在输入框上方，不像浮动标签那样跳走', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(GlassField(controller: controller, label: '标题', hintText: '一句话说明你的主题')),
    );

    expect(find.text('标题'), findsOneWidget);
    // label 在输入框上面，不是 hint 那种「框内占位」。
    final labelY = tester.getCenter(find.text('标题')).dy;
    final fieldY = tester.getCenter(find.byType(TextField)).dy;
    expect(labelY, lessThan(fieldY));

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('标题'), findsOneWidget);
    expect(tester.getCenter(find.text('标题')).dy, labelY);
  });

  testWidgets('聚焦时描边转主色，失去焦点再退回去', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(wrap(GlassField(controller: controller, hintText: 'x')));

    Color borderColor() {
      final box = tester.widget<AnimatedContainer>(
        find.descendant(of: find.byType(GlassField), matching: find.byType(AnimatedContainer)),
      );
      return ((box.decoration! as BoxDecoration).border! as Border).top.color;
    }

    final idle = borderColor();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final focused = borderColor();
    expect(focused, isNot(idle));

    // 失焦后恢复成发丝描边。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(borderColor(), idle);
  });

  testWidgets('输入内容写回 controller', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(wrap(GlassField(controller: controller)));

    await tester.enterText(find.byType(TextField), '求助：如何提取签名');
    await tester.pump();
    expect(controller.text, '求助：如何提取签名');
  });

  testWidgets('密码框会遮蔽输入', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(wrap(GlassField(controller: controller, obscureText: true)));
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
  });

  testWidgets('多行输入不留单行光标高度', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(wrap(GlassField(controller: controller, minLines: 6, maxLines: null)));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.minLines, 6);
    expect(field.maxLines, isNull);
    expect(field.cursorHeight, isNull);
  });

  testWidgets('GlassSelectRow 点了会回调，值显示在行上', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      wrap(GlassSelectRow(value: '交流与讨论 / 逆向交流', onTap: () => tapped++)),
    );

    expect(find.text('交流与讨论 / 逆向交流'), findsOneWidget);
    await tester.tap(find.byType(GlassSelectRow));
    expect(tapped, 1);
  });

  testWidgets('GlassSelectRow 没值时显示占位文案', (tester) async {
    await tester.pumpWidget(wrap(GlassSelectRow(value: null, placeholder: '选择一个版块', onTap: _noop)));
    expect(find.text('选择一个版块'), findsOneWidget);
  });

  testWidgets('showGlassOptionSheet 选完把值回传', (tester) async {
    int? picked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                picked = await showGlassOptionSheet<int>(
                  context,
                  title: '安全提问',
                  options: const [(0, '无安全提问'), (1, '母亲的名字')],
                  selected: 0,
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('安全提问'), findsOneWidget);

    await tester.tap(find.text('母亲的名字'));
    await tester.pumpAndSettle();
    expect(picked, 1);
    expect(find.text('安全提问'), findsNothing);
  });
}

void _noop() {}
