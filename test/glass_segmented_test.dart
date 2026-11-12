import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/glass_controls.dart';

/// 玻璃分段控件。
///
/// 全站原来混着三种「二选一 / 多选一」：Material 的 `SegmentedButton`、
/// 手写的下划线 tab、`DropdownButton`。同一个功能三种长相，这里统一成
/// 一整块淡玻璃 + 选中那段浮起。
void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: Container(
            color: Colors.teal.shade200,
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      );

  testWidgets('渲染每一段，选中的那段主色加粗', (tester) async {
    await tester.pumpWidget(wrap(GlassSegmented<bool>(
      segments: const [(false, '全部'), (true, '热销')],
      value: true,
      onChanged: (_) {},
    )));

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('热销'), findsOneWidget);

    TextStyle styleOf(String label) => tester.widget<Text>(find.text(label)).style!;
    expect(styleOf('热销').color, isNot(styleOf('全部').color));
    expect(styleOf('热销').fontWeight, FontWeight.w700);
    expect(styleOf('全部').fontWeight, FontWeight.w500);
  });

  testWidgets('点另一段把值回调出去', (tester) async {
    bool? picked;
    await tester.pumpWidget(wrap(GlassSegmented<bool>(
      segments: const [(false, '全部'), (true, '热销')],
      value: false,
      onChanged: (value) => picked = value,
    )));

    await tester.tap(find.text('热销'));
    expect(picked, isTrue);
  });

  testWidgets('onChanged 为 null 时整组禁用，点了没反应', (tester) async {
    await tester.pumpWidget(wrap(const GlassSegmented<int>(
      segments: [(0, '低'), (1, '中'), (2, '高')],
      value: 1,
      onChanged: null,
    )));

    await tester.tap(find.text('高'));
    await tester.pump();
    // 没有回调、也没有异常，选中态仍是原来的「中」。
    final selected = tester.widget<Text>(find.text('中')).style!;
    expect(selected.fontWeight, FontWeight.w700);
  });

  testWidgets('expand 时每段等分，不 expand 时按内容收缩', (tester) async {
    await tester.pumpWidget(wrap(SizedBox(
      width: 320,
      child: GlassSegmented<bool>(
        segments: const [(false, '发表帖子'), (true, '发投票')],
        value: false,
        expand: true,
        onChanged: (_) {},
      ),
    )));
    final wide = tester.getSize(find.byType(GlassSegmented<bool>)).width;
    expect(wide, 320);

    await tester.pumpWidget(wrap(GlassSegmented<bool>(
      segments: const [(false, '全部'), (true, '热销')],
      value: false,
      onChanged: (_) {},
    )));
    final narrow = tester.getSize(find.byType(GlassSegmented<bool>)).width;
    expect(narrow, lessThan(320));
    expect(narrow, greaterThan(80));
  });

  testWidgets('dense 比常规模式矮', (tester) async {
    await tester.pumpWidget(wrap(GlassSegmented<bool>(
      segments: const [(false, '全部'), (true, '热销')],
      value: false,
      onChanged: (_) {},
    )));
    final normal = tester.getSize(find.byType(GlassSegmented<bool>)).height;

    await tester.pumpWidget(wrap(GlassSegmented<bool>(
      segments: const [(false, '全部'), (true, '热销')],
      value: false,
      dense: true,
      onChanged: (_) {},
    )));
    final compact = tester.getSize(find.byType(GlassSegmented<bool>)).height;

    expect(compact, lessThan(normal));
  });
}
