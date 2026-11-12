import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/state/app_state.dart';
import 'package:mt_forum/ui/widgets/glass_dialog.dart';
import 'package:mt_forum/ui/widgets/thread_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 玻璃对话框：底板是玻璃、返回值正确。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.threadGlassOpacity = 0.55;
    AppState.instance.threadGlassBlur = 22;
  });

  /// 一个带按钮的页面；按钮点下去弹 [open] 给出的对话框。
  Widget host(Future<void> Function(BuildContext) open) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => open(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
  }

  Widget confirmBody(BuildContext ctx) => GlassDialog(
        title: const Text('删除下载记录'),
        content: const Text('同时删除本地文件？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      );

  testWidgets('弹出来是一块玻璃，不是 Material 白卡片', (tester) async {
    await tester.pumpWidget(host((context) async {
      await showGlassDialog<bool>(context: context, builder: confirmBody);
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('删除下载记录'), findsOneWidget);
    expect(find.byType(GlassBackdrop), findsWidgets);

    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    // 底色交给外层玻璃，Dialog 自己不铺。
    expect(dialog.backgroundColor, Colors.transparent);
    expect(dialog.elevation, 0);

    // 玻璃底板只包住卡片本身，不能撑满整屏——撑满会把整页糊掉。
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final backdrop = tester.getRect(find.byType(GlassBackdrop).last);
    expect(backdrop.width, lessThan(screen.width));
    expect(backdrop.height, lessThan(screen.height));
  });

  testWidgets('取消返回 false，确认返回 true', (tester) async {
    bool? answered;
    await tester.pumpWidget(host((context) async {
      answered = await showGlassDialog<bool>(context: context, builder: confirmBody);
    }));
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(answered, isFalse);

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(answered, isTrue);
  });

  testWidgets('点遮罩关闭（默认可关闭）', (tester) async {
    await tester.pumpWidget(host((context) async {
      await showGlassDialog<bool>(context: context, builder: confirmBody);
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('删除下载记录'), findsNothing);
  });

  testWidgets('barrierDismissible 为 false 时点遮罩不关', (tester) async {
    await tester.pumpWidget(host((context) async {
      await showGlassDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const GlassDialog(
          title: Text('请稍候'),
          content: Text('正在处理'),
        ),
      );
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('请稍候'), findsOneWidget);
  });

  testWidgets('正文用高对比度前景色，不能是次级灰', (tester) async {
    await tester.pumpWidget(host((context) async {
      await showGlassDialog<bool>(context: context, builder: confirmBody);
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final paragraph = tester.renderObject<RenderParagraph>(find.text('同时删除本地文件？'));
    final style = paragraph.text.style!;
    // 玻璃是半透明的，底下还压着页面正文；次级灰、甚至带一点 alpha 的
    // onSurface 都会在背景上被稀释成灰字，这里要求完全不透明。
    expect(style.color!.a, 1.0, reason: '正文不能再用任何半透明的颜色');
    expect(style.fontSize, greaterThanOrEqualTo(15));
  });

  testWidgets('两个动作按钮等宽同高，不再一大一小', (tester) async {
    await tester.pumpWidget(host((context) async {
      await showGlassDialog<bool>(context: context, builder: confirmBody);
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final cancel = tester.getSize(find.widgetWithText(TextButton, '取消'));
    final confirm = tester.getSize(find.widgetWithText(FilledButton, '删除'));
    // 一个文字按钮配一个填充胶囊，宽度差一大截，视觉上像没对齐。
    expect((cancel.width - confirm.width).abs(), lessThan(0.5));
    expect(cancel.height, confirm.height);
    expect(cancel.height, greaterThanOrEqualTo(44));
  });

  testWidgets('全局玻璃调得再透，对话框也守住可读性下限', (tester) async {
    // 设置面板允许把不透明度拖到 0.05、模糊拖到 0——这时背后是一张彩色
    // 封面，文字等于直接印在图上。对话框必须自己兜底。
    AppState.instance.threadGlassOpacity = 0.05;
    AppState.instance.threadGlassBlur = 0;

    await tester.pumpWidget(host((context) async {
      await showGlassDialog<bool>(context: context, builder: confirmBody);
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final backdrop = tester.widget<GlassBackdrop>(find.byType(GlassBackdrop).last);
    expect(backdrop.opacity, greaterThanOrEqualTo(0.8));
    expect(backdrop.blur, greaterThanOrEqualTo(20));
  });
}
