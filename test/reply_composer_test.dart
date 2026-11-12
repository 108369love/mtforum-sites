import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/reply_composer.dart';
import 'package:mt_forum/ui/widgets/thread_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回复栏的版式契约。
///
/// 这一条横在正文底下的小胶囊挤了五样东西（表情、输入、插图、发送、引用条），
/// 任何一处多几个 dp 都会在窄屏上把别的挤扁，靠肉眼回归很难盯住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// 测试画布默认 800x600，是个平板尺寸，窄屏才会暴露的挤压问题看不出来。
  void useSurface(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width * 3, 700 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  const panelKey = Key('emoji-panel');

  Widget host({
    required TextEditingController controller,
    FocusNode? focus,
    String? author,
    String? floor,
    int attachments = 0,
    bool emoji = false,
    bool sending = false,
    bool uploading = false,
    VoidCallback? onSend,
    VoidCallback? onAttach,
    VoidCallback? onToggleEmoji,
    VoidCallback? onClearReplyTarget,
  }) {
    return MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ReplyComposer(
                  controller: controller,
                  focusNode: focus ?? FocusNode(),
                  replyToAuthor: author,
                  replyToFloor: floor,
                  attachmentCount: attachments,
                  sending: sending,
                  uploading: uploading,
                  showEmoji: emoji,
                  onSend: onSend ?? () {},
                  onAttach: onAttach ?? () {},
                  onToggleEmoji: onToggleEmoji ?? () {},
                  onClearReplyTarget: onClearReplyTarget ?? () {},
                  emojiPanel: const SizedBox(key: panelKey, height: 120),
                ),
              ),
            ],
          ),
        ),
    );
  }

  Rect boxOf(WidgetTester tester) => tester.getRect(find.byType(GlassBackdrop));

  testWidgets('没写字时发送键是暗的、按不动；写了才点亮', (tester) async {
    useSurface(tester, 390);
    final controller = TextEditingController();
    var sent = 0;
    await tester.pumpWidget(host(controller: controller, onSend: () => sent++));
    await tester.pumpAndSettle();

    final idleColor = tester.widget<Icon>(find.byIcon(Icons.send_rounded)).color;
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(sent, 0, reason: '空内容不该发出去，也不该弹「请输入回复内容」');

    controller.text = '看看';
    await tester.pump();
    final litColor = tester.widget<Icon>(find.byIcon(Icons.send_rounded)).color;
    expect(litColor, isNot(idleColor), reason: '有内容时发送键要换成主色上的字');

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(sent, 1);
  });

  testWidgets('只有空白字符不算有内容', (tester) async {
    useSurface(tester, 390);
    final controller = TextEditingController(text: '   \n  ');
    var sent = 0;
    await tester.pumpWidget(host(controller: controller, onSend: () => sent++));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(sent, 0);
  });

  testWidgets('回复某楼时顶上一根引用条，写清是谁的哪一楼', (tester) async {
    useSurface(tester, 390);
    final controller = TextEditingController();
    var cleared = 0;
    await tester.pumpWidget(
      host(
        controller: controller,
        author: 'Binary_涛',
        floor: '3楼',
        onClearReplyTarget: () => cleared++,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Binary_涛', findRichText: true), findsOneWidget);
    expect(find.textContaining('3楼', findRichText: true), findsOneWidget);

    await tester.tap(find.byTooltip('取消回复'));
    await tester.pump();
    expect(cleared, 1);
  });

  testWidgets('不回复某楼时没有引用条，胶囊也就矮一截', (tester) async {
    useSurface(tester, 390);
    final controller = TextEditingController();
    await tester.pumpWidget(host(controller: controller));
    await tester.pumpAndSettle();
    final idle = boxOf(tester).height;

    await tester.pumpWidget(host(controller: controller, author: 'Binary_涛', floor: '3楼'));
    await tester.pumpAndSettle();
    expect(boxOf(tester).height, greaterThan(idle));
    expect(find.byTooltip('取消回复'), findsOneWidget);
  });

  testWidgets('表情面板跟着 showEmoji 出现和收起', (tester) async {
    useSurface(tester, 390);
    final controller = TextEditingController();
    var toggled = 0;
    await tester.pumpWidget(
      host(controller: controller, onToggleEmoji: () => toggled++),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(panelKey), findsNothing);
    final closed = boxOf(tester).height;

    await tester.tap(find.byTooltip('表情'));
    await tester.pump();
    expect(toggled, 1, reason: '按钮只负责回调，展开与否由页面决定');

    await tester.pumpWidget(host(controller: controller, emoji: true));
    await tester.pumpAndSettle();
    expect(find.byKey(panelKey), findsOneWidget);
    expect(boxOf(tester).height, greaterThan(closed));
  });

  testWidgets('插过图就在图片键上挂角标', (tester) async {
    useSurface(tester, 390);
    final controller = TextEditingController();
    await tester.pumpWidget(host(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsNothing);

    await tester.pumpWidget(host(controller: controller, attachments: 2));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    // 角标不能压到右边的发送键上。
    final badge = tester.getRect(find.text('2'));
    final send = tester.getRect(find.byIcon(Icons.send_rounded));
    expect(badge.right, lessThan(send.left + 2));
  });

  testWidgets('胶囊是浮起来的圆角玻璃，没有满宽铺满', (tester) async {
    useSurface(tester, 390);
    final controller = TextEditingController();
    await tester.pumpWidget(host(controller: controller));
    await tester.pumpAndSettle();

    final glass = tester.widget<GlassBackdrop>(find.byType(GlassBackdrop));
    expect(glass.borderRadius, BorderRadius.circular(26));
    expect(glass.showShadow, isFalse, reason: '阴影会从半透明面板里透出来，把整条压成灰板');

    final rect = boxOf(tester);
    expect(rect.left, greaterThan(0), reason: '两侧要留边，正文才能从胶囊背后透出来');
    expect(rect.right, lessThan(390));
    expect(tester.takeException(), isNull);
  });

  testWidgets('输入区直接写在玻璃上，不再套一层浅色方框', (tester) async {
    useSurface(tester, 390);
    final controller = TextEditingController();
    await tester.pumpWidget(host(controller: controller));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.border, InputBorder.none);
    expect(field.decoration?.enabledBorder, InputBorder.none);
    expect(field.decoration?.focusedBorder, InputBorder.none);
    // 这里必须断言「等于 false」而不是「不是 true」：`filled` 留空会从
    // `InputDecorationTheme` 继承 true，写 `?? false` 会白白放过那个方块。
    expect(field.decoration?.filled, isFalse, reason: '输入框自己也不能铺底色，主题里的 filled 会被继承');
    expect(field.maxLines, 5);

    // 整条回复栏里会动的那层底只剩发送键一颗；再冒出一个，就是方框又回来了。
    expect(find.byType(AnimatedContainer), findsOneWidget);
  });

  testWidgets('单行时输入框和两边的键一样高，看着是一条横线', (tester) async {
    useSurface(tester, 390);
    final controller = TextEditingController();
    await tester.pumpWidget(host(controller: controller));
    await tester.pumpAndSettle();

    final field = tester.getRect(find.byType(TextField));
    final emoji = tester.getRect(find.byTooltip('表情'));
    final send = tester.getRect(find.byType(AnimatedContainer));
    expect(field.height, closeTo(emoji.height, 0.5));
    expect(send.height, closeTo(field.height, 0.5));

    // 三颗键的底线也要齐：多行时输入框往上长，键贴着底走。
    expect(emoji.bottom, closeTo(send.bottom, 0.5));
  });

  testWidgets('320 窄屏也放得下，文字区还有可用的宽度', (tester) async {
    useSurface(tester, 320);
    final controller = TextEditingController(text: '窄屏也要能写字');
    await tester.pumpWidget(
      host(controller: controller, author: 'Binary_涛', floor: '3楼', attachments: 3),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final field = tester.getRect(find.byType(TextField));
    expect(field.width, greaterThan(140), reason: '表情、插图、发送三个键不该把输入区挤没');
  });
}
