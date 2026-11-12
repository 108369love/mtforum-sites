import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/sign_in_status.dart';
import 'package:mt_forum/state/app_state.dart';
import 'package:mt_forum/ui/widgets/sign_in_badge.dart';

void main() {
  group('签到日期判定', () {
    test('日期键补零到 YYYY-MM-DD', () {
      expect(signInDayKey(DateTime(2026, 10, 31, 23, 59)), '2026-10-31');
      expect(signInDayKey(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('同一天算已签，跨零点就算没签', () {
      final saved = signInDayKey(DateTime(2026, 10, 31, 0, 5));
      expect(signedInOn(saved, DateTime(2026, 10, 31, 23, 59)), isTrue);
      expect(signedInOn(saved, DateTime(2026, 11, 1, 0, 1)), isFalse);
    });

    test('没有本地记录时视为未签', () {
      expect(signedInOn(null, DateTime(2026, 10, 31)), isFalse);
    });
  });

  group('签到条', () {
    testWidgets('未签到时给出「点我签到」并响应点击', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SignInBadge(signedIn: false, onSignIn: () => tapped++),
        ),
      ));

      expect(find.text('今日未签到'), findsOneWidget);
      expect(find.text('点我签到'), findsOneWidget);

      await tester.tap(find.byType(SignInBadge));
      expect(tapped, 1);
    });

    testWidgets('已签到只展示状态，不再让人点', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SignInBadge(signedIn: true, onSignIn: () => tapped++),
        ),
      ));

      expect(find.text('今日已签到'), findsOneWidget);
      expect(find.text('点我签到'), findsNothing);

      await tester.tap(find.byType(SignInBadge));
      expect(tapped, 0);
    });

    testWidgets('请求进行中转圈，不再显示可点文案', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SignInBadge(signedIn: false, busy: true, onSignIn: () {}),
        ),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('点我签到'), findsNothing);
    });
  });

  test('未登录时手动签到直接提示，不发起请求', () async {
    expect(AppState.instance.isLoggedIn, isFalse);
    expect(await AppState.instance.signInNow(), '请先登录后再签到');
  });
}
