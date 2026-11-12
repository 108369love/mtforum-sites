import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/models.dart';
import 'package:mt_forum/ui/pages/search_page.dart';
import 'package:mt_forum/ui/widgets/board_picker_sheet.dart';
import 'package:mt_forum/ui/widgets/thread_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 搜索页的版块筛选从「铺满全屏的下拉菜单」改成了玻璃浮层。
///
/// 这组测试盯两件事：下拉菜单不许回来；浮层要按分区列出全部版块、选中能回传。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const categories = [
    ForumCategory(name: 'MT专区', boards: [
      ForumBoard(fid: 1, name: '版本发布'),
      ForumBoard(fid: 3, name: '建议反馈'),
    ]),
    ForumCategory(name: '交流与讨论', boards: [
      ForumBoard(fid: 4, name: '逆向交流'),
      ForumBoard(fid: 6, name: '编程开发'),
    ]),
  ];

  Future<int?> openSheet(WidgetTester tester) async {
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await showModalBottomSheet<int>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => const BoardPickerSheet(categories: categories, selected: 0),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('搜索页不再用下拉菜单筛选版块', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.pump();
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    // 搜索框和搜索按钮还在。
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsWidgets);
  });

  testWidgets('浮层是玻璃，且不占满整屏', (tester) async {
    await openSheet(tester);

    expect(find.byType(BoardPickerSheet), findsOneWidget);
    expect(
      find.descendant(of: find.byType(BoardPickerSheet), matching: find.byType(GlassBackdrop)),
      findsOneWidget,
      reason: '浮层底板要是玻璃，不是一块不透明面板',
    );

    final sheet = tester.getRect(find.byType(BoardPickerSheet));
    final screen = tester.getSize(find.byType(MaterialApp));
    expect(sheet.height, lessThan(screen.height * 0.8), reason: '浮层不该铺满整屏，留下背后的内容给玻璃去糊');
  });

  testWidgets('浮层按分区列出全部版块', (tester) async {
    await openSheet(tester);

    expect(find.text('选择版块'), findsOneWidget);
    expect(find.text('全部版块'), findsOneWidget);
    expect(find.text('MT专区'), findsOneWidget);
    expect(find.text('交流与讨论'), findsOneWidget);
    for (final name in ['版本发布', '建议反馈', '逆向交流', '编程开发']) {
      expect(find.text(name), findsOneWidget, reason: '$name 应该出现在浮层里');
    }
  });

  testWidgets('选中版块后把 fid 回传给页面', (tester) async {
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await showModalBottomSheet<int>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => const BoardPickerSheet(categories: categories, selected: 0),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('逆向交流'));
    await tester.pumpAndSettle();

    expect(picked, 4);
    expect(find.text('选择版块'), findsNothing, reason: '选完要收起来');
  });
}
