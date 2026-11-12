import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/models.dart';
import 'package:mt_forum/state/app_state.dart';
import 'package:mt_forum/ui/pages/compose_page.dart';
import 'package:mt_forum/ui/pages/login_page.dart';
import 'package:mt_forum/ui/widgets/board_picker_sheet.dart';
import 'package:mt_forum/ui/widgets/glass_app_bar.dart';
import 'package:mt_forum/ui/widgets/glass_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 登录页 / 发帖页的表单。
///
/// 这两页是 App 里仅剩的两个「表单页」，之前整页都是 Material 默认控件：
/// 带下划线的输入框、会铺满屏幕的下拉菜单、两个撑满宽度的大按钮。玻璃
/// 页面上横着几道深色下划线，一眼就能看出是另一套风格。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const categories = [
    ForumCategory(
      name: '交流与讨论',
      boards: [
        ForumBoard(fid: 11, name: '逆向交流'),
        ForumBoard(fid: 12, name: '玩机交流'),
      ],
    ),
    ForumCategory(
      name: '资源分享',
      boards: [ForumBoard(fid: 21, name: '软件分享')],
    ),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.debugSetBoards(categories);
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pumpAndSettle();
  }

  Future<void> pumpCompose(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ComposePage()));
    await tester.pumpAndSettle();
  }

  group('登录页', () {
    testWidgets('顶栏是玻璃的，正文从它背后滚过', (tester) async {
      await pumpLogin(tester);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.extendBodyBehindAppBar, isTrue);
      expect(find.byType(GlassAppBar), findsOneWidget);
    });

    testWidgets('用户名和密码都是玻璃输入框', (tester) async {
      await pumpLogin(tester);

      final fields = tester.widgetList<GlassField>(find.byType(GlassField)).toList();
      expect(fields.length, greaterThanOrEqualTo(2));
      expect(fields[0].label, '用户名');
      expect(fields[1].label, '密码');
      expect(fields[1].obscureText, isTrue);
    });

    testWidgets('安全提问是选择行，点开是玻璃浮层而不是下拉菜单', (tester) async {
      await pumpLogin(tester);

      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(find.byType(GlassSelectRow), findsOneWidget);
      expect(find.text('无安全提问'), findsOneWidget);

      await tester.tap(find.byType(GlassSelectRow));
      await tester.pumpAndSettle();
      expect(find.byType(BoardPickerSheet), findsNothing);
      expect(find.text('母亲的名字'), findsOneWidget);

      await tester.tap(find.text('母亲的名字'));
      await tester.pumpAndSettle();
      expect(find.text('母亲的名字'), findsOneWidget);
      // 选完安全提问，答案输入框跟着出现。
      final fields = tester.widgetList<GlassField>(find.byType(GlassField)).toList();
      expect(fields.any((e) => e.label == '安全提问答案'), isTrue);
    });

    testWidgets('账号留空直接登录会提示，不发起请求', (tester) async {
      await pumpLogin(tester);

      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();
      expect(find.text('请输入用户名和密码'), findsOneWidget);
    });
  });

  group('发帖页', () {
    testWidgets('「发布到」是玻璃选择行，不是下拉表单', (tester) async {
      await pumpCompose(tester);

      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      final row = tester.widget<GlassSelectRow>(find.byType(GlassSelectRow));
      expect(row.label, '发布到');
      // 默认落在第一个版块，行上直接显示「分区 / 版块」。
      expect(row.value, '交流与讨论 / 逆向交流');
    });

    testWidgets('点「发布到」弹出分区浮层，发帖没有「全部版块」', (tester) async {
      await pumpCompose(tester);

      await tester.tap(find.byType(GlassSelectRow));
      await tester.pumpAndSettle();

      expect(find.byType(BoardPickerSheet), findsOneWidget);
      expect(find.text('全部版块'), findsNothing);
      expect(find.text('交流与讨论'), findsOneWidget);
      expect(find.text('资源分享'), findsOneWidget);
    });

    testWidgets('换版块后行上跟着变', (tester) async {
      await pumpCompose(tester);

      await tester.tap(find.byType(GlassSelectRow));
      await tester.pumpAndSettle();
      await tester.tap(find.text('软件分享'));
      await tester.pumpAndSettle();

      final row = tester.widget<GlassSelectRow>(find.byType(GlassSelectRow));
      expect(row.value, '资源分享 / 软件分享');
    });

    testWidgets('标题、标签、正文都是玻璃输入框', (tester) async {
      await pumpCompose(tester);

      final fields = tester.widgetList<GlassField>(find.byType(GlassField)).toList();
      expect(fields.map((e) => e.label).whereType<String>().toList(), ['标题', '主题标签（可选）']);
      final body = fields.firstWhere((e) => e.label == null);
      expect(body.minLines, 8);
      expect(body.maxLines, isNull);
    });

    testWidgets('底部不再是两个撑满宽度的大按钮', (tester) async {
      await pumpCompose(tester);

      // 整页只剩「发表」一个 FilledButton，「草稿」退成玻璃次级按钮。
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('发表'), findsOneWidget);
      expect(find.text('草稿'), findsOneWidget);
      expect(find.text('保存草稿'), findsNothing);
    });

    testWidgets('帖子 / 投票是分段控件，切到投票才出投票编辑区', (tester) async {
      await pumpCompose(tester);

      expect(find.text('发表帖子'), findsOneWidget);
      expect(find.text('发投票'), findsOneWidget);
      expect(find.text('投票选项'), findsNothing);

      await tester.tap(find.text('发投票'));
      await tester.pumpAndSettle();
      expect(find.text('投票选项'), findsOneWidget);
    });
  });
}
