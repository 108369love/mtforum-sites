import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';

/// 表格曾经被塞进横向滚动容器里渲染：无限宽约束下 Table 的列宽会塌到
/// 只剩单元格 padding，文字被挤成一行一个字（看着像竖排乱码），整张参数表
/// 变成一根窄条，右边留出大片空白。这里守住「列宽正常 + 表格铺满屏宽」。
void main() {
  const screenWidth = 360.0;

  Future<void> pumpHtml(WidgetTester tester, String html) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: PostHtmlView(html: html))),
    ));
    await tester.pump();
  }

  testWidgets('两列参数表：列宽正常、文字不竖排', (tester) async {
    await pumpHtml(tester, '''
      <table>
        <tr><th>项目</th><th>内容</th></tr>
        <tr><td>应用名称</td><td>MT管理器</td></tr>
        <tr><td>版本</td><td>bate1.0（一代版 修复版）</td></tr>
        <tr><td>包名</td><td>bin.mt</td></tr>
        <tr><td>体积</td><td>约 607 KB</td></tr>
        <tr><td>签名状态</td><td>已签名（v1 + v2）</td></tr>
      </table>
    ''');

    final cell = tester.getSize(find.text('bate1.0（一代版 修复版）'));
    // 塌缩时宽度只有 0，文字被逐字挤成一行一个。
    expect(cell.width, greaterThan(60));
    expect(cell.height, lessThan(80));

    final table = tester.getSize(find.byType(Table));
    expect(table.width, lessThanOrEqualTo(screenWidth + 0.5));
    // 五行的小表不该撑出几百像素高的空白。
    expect(table.height, lessThan(260));
  });

  testWidgets('单元格按内容分列，短列不被长列挤没', (tester) async {
    await pumpHtml(tester, '''
      <table>
        <tr><td>版本</td><td>bate1.0</td></tr>
        <tr><td>包名</td><td>bin.mt</td></tr>
      </table>
    ''');

    final label = tester.getSize(find.text('版本'));
    final value = tester.getSize(find.text('bate1.0'));
    expect(label.width, greaterThan(40));
    expect(value.width, greaterThan(label.width));
  });

  testWidgets('列特别多时改为横向滚动，而不是把每列压成一条线', (tester) async {
    const header = '<tr><th>A</th><th>B</th><th>C</th><th>D</th><th>E</th><th>F</th></tr>';
    const row = '<tr><td>111111</td><td>222222</td><td>333333</td><td>444444</td><td>555555</td><td>666666</td></tr>';
    await pumpHtml(tester, '<table>$header$row</table>');

    final table = tester.getSize(find.byType(Table));
    expect(table.width, greaterThan(screenWidth));
    // 每列至少 72，六列总宽 432，不会塌成一根竖条。
    expect(table.width, greaterThanOrEqualTo(430));

    final cell = tester.getSize(find.text('111111'));
    expect(cell.width, greaterThan(40));
  });

  testWidgets('空单元格与不齐的行数不会崩', (tester) async {
    await pumpHtml(tester, '<table><tr><td>只有一格</td></tr><tr><td>两格</td><td></td></tr></table>');
    expect(find.text('只有一格'), findsOneWidget);
    expect(find.text('两格'), findsOneWidget);
  });
}
