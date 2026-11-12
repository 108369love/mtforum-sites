import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/http_session.dart';
import 'package:mt_forum/ui/widgets/cookie_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpSession session;
  String? clipboard;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    session = HttpSession.instance;
    session.clear();
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': clipboard};
      }
      return null;
    });
  });

  tearDown(() {
    session.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// 把对话框挂在一个按钮上，点开再断言——和「我的」页里的真实入口一致。
  Future<bool?> open(WidgetTester tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async => result = await showCookieDialog(context, session: session),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('对话框里是完整的一串 cookie，逐条都在', (tester) async {
    session.setCookie('xx_auth', 'abc123');
    session.setCookie('saltkey', 'SALT');
    await open(tester);

    expect(find.text('复制 Cookie'), findsOneWidget);
    expect(find.textContaining('共 2 项'), findsOneWidget);
    // 复制出去的东西要能原样贴回去，顺序按写入顺序，和请求头一致。
    expect(find.text('xx_auth=abc123; saltkey=SALT'), findsOneWidget);
  });

  testWidgets('点复制把整串写进剪贴板，并关掉对话框', (tester) async {
    session.setCookie('xx_auth', 'abc123');
    session.setCookie('acw_sc__v2', 'waf');
    await open(tester);

    await tester.tap(find.widgetWithText(FilledButton, '复制'));
    await tester.pumpAndSettle();

    expect(clipboard, 'xx_auth=abc123; acw_sc__v2=waf');
    expect(find.text('复制 Cookie'), findsNothing);
  });

  testWidgets('取消不碰剪贴板', (tester) async {
    session.setCookie('xx_auth', 'abc123');
    await open(tester);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(clipboard, isNull);
  });

  testWidgets('一条 cookie 都没有时，复制按钮不可用', (tester) async {
    await open(tester);

    expect(find.textContaining('还没有存下任何 Cookie'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '复制'));
    expect(button.onPressed, isNull);
    expect(clipboard, isNull);
  });

  test('cookieNames 按名字排序，cookieCount 跟着增减', () {
    session.setCookie('z_cookie', '1');
    session.setCookie('a_cookie', '2');
    expect(session.cookieCount, 2);
    expect(session.cookieNames, ['a_cookie', 'z_cookie']);

    session.removeCookie('z_cookie');
    expect(session.cookieCount, 1);
    expect(session.cookieNames, ['a_cookie']);
  });
}
