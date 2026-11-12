import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/pages/about_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 关于页的外链清单。
///
/// 关于页最容易漏东西：加了个入口没人看，改地址又没人点。这里只钉两件最
/// 容易回归的事——开源地址这一行还在，且和站点、管理器一样走"点开新窗口"
/// 那一套。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('关于页挂出本项目的开源地址', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pump();

    expect(find.text('开源地址'), findsOneWidget);
    expect(find.text('github.com/Aioprh/mtforum-app'), findsOneWidget);

    // 论坛、MT管理器、开源地址三行都是外链，图标要一致。
    expect(find.byIcon(Icons.open_in_new_rounded), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
