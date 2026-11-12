import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/app_theme.dart';
import 'package:mt_forum/ui/pages/thread_page.dart';

/// 主题里 FilledButton 的 minimumSize 是 `Size.fromHeight(50)`（宽度无穷大），
/// 放进 Row 会把同一行的提示文字压成竖排，所以面板里改成整宽按钮 + 单独一行说明。
void main() {
  testWidgets('举报面板在窄屏上不会把说明文字挤成竖排', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => const ReportSheet(floor: '15楼'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('提交举报'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final button = tester.getSize(find.widgetWithText(FilledButton, '提交举报'));
    expect(button.width, lessThanOrEqualTo(360));
    expect(button.height, lessThan(60));

    // 说明文字应当是一行，竖排时高度会成倍增长。
    final hint = tester.getSize(find.text('举报会提交给版主和管理员处理'));
    expect(hint.height, lessThan(40));
  });
}
