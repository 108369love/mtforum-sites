import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/pages/image_viewer_page.dart';

/// 图片查看页的下滑关闭。
///
/// 系统返回手势只认左右边缘，横滑翻图也吃那一片，两者抢指针。下滑关闭是
/// 给用户另一条不碰边缘的退出路径，所以这里要盯住两件事：竖着拖能关、
/// 横着拖不能误关。
void main() {
  Future<void> openViewer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const ImageViewerPage(
                      images: <String>['https://example.invalid/a.jpg'],
                    ),
                  ),
                ),
                child: const Text('看图'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('看图'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerPage), findsOneWidget);
  }

  testWidgets('向下拖过阈值会关闭页面', (tester) async {
    await openViewer(tester);
    // 默认测试画布 800x600，阈值是 600 * 0.18 = 108。
    await tester.drag(find.byType(ImageViewerPage), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerPage), findsNothing);
  });

  testWidgets('拖得不够远会回弹，不关页面', (tester) async {
    await openViewer(tester);
    await tester.drag(find.byType(ImageViewerPage), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerPage), findsOneWidget);
  });

  testWidgets('横向拖动不触发关闭，留给翻页', (tester) async {
    await openViewer(tester);
    await tester.drag(find.byType(ImageViewerPage), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerPage), findsOneWidget);
  });

  testWidgets('向上拖不触发关闭', (tester) async {
    await openViewer(tester);
    await tester.drag(find.byType(ImageViewerPage), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerPage), findsOneWidget);
  });
}
