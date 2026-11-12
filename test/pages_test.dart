import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/pages/followers_page.dart';
import 'package:mt_forum/ui/pages/native_notice_category_page.dart';
import 'package:mt_forum/ui/pages/notifications_page.dart';

/// 未登录时三个入口都应落到「登录后查看」的原生空状态，不发起网络请求。
void main() {
  Future<void> pump(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump();
  }

  testWidgets('消息提醒入口可以渲染', (tester) async {
    await pump(tester, const NotificationsPage());
    expect(find.text('坛友互动'), findsOneWidget);
    expect(find.text('我的粉丝'), findsOneWidget);
  });

  testWidgets('提醒列表未登录时提示登录', (tester) async {
    await pump(tester, const NativeNoticeCategoryPage(title: '坛友互动', view: 'friend'));
    expect(find.text('登录后查看消息提醒'), findsOneWidget);
  });

  testWidgets('粉丝列表未登录时提示登录', (tester) async {
    await pump(tester, const FollowersPage());
    expect(find.text('登录后查看我的粉丝'), findsOneWidget);
  });
}
