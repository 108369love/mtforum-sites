import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/pages/compose_page.dart';
import 'package:mt_forum/ui/widgets/measure_height.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 悬浮玻璃条的高度必须量出来，不能写死。
///
/// 回复框、私信输入条、发帖工具条都浮在列表上层，列表得在内容末尾给它们
/// 让出同样多的位置。写死一个常数只对初始形态成立：输入框换行、表情面板
/// 展开之后，高度一变，最后一条内容就被压在玻璃底下了。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('首帧量出高度，子组件长高后跟着回调', (tester) async {
    final heights = <double>[];

    Widget build(double height) {
      return MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MeasureHeight(
              onHeight: heights.add,
              child: SizedBox(height: height, width: 100),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(48));
    await tester.pump();
    expect(heights, [48]);

    await tester.pumpWidget(build(96));
    await tester.pump();
    expect(heights.last, 96);

    // 高度没变就不该回调，否则每帧都会顶着父页面重构。
    await tester.pumpWidget(build(96));
    await tester.pump();
    expect(heights.length, 2);
  });

  testWidgets('发帖页展开面板后，正文底部留白跟着变大', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ComposePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    double listBottom() {
      final list = tester.widget<ListView>(find.byType(ListView).first);
      return (list.padding! as EdgeInsets).bottom;
    }

    final before = listBottom();

    // 展开表情面板：工具条整体变高，正文要让出更多位置。
    await tester.tap(find.byIcon(Icons.sentiment_satisfied_alt_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final after = listBottom();
    expect(after, greaterThan(before), reason: '面板展开后正文末尾要给工具条让出更多高度');
    expect(tester.takeException(), isNull);
  });
}
