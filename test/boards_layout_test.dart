import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/models.dart';
import 'package:mt_forum/ui/pages/boards_page.dart';

/// 版块页的间距契约。
///
/// 曾经的 bug：分区标题和第一行卡片之间空出一百多 dp。原因是网格没写
/// padding，GridView 就把 MediaQuery 的安全区当成了自己的内边距；这页开了
/// extendBodyBehindAppBar，body 拿到的顶部安全区等于「状态栏 + 顶栏」，
/// 于是一整屏高度里只塞得下两三个分区，其它全是空白。
///
/// 这里用带安全区的 MediaQuery 复现真机环境，标题到卡片必须紧挨着。
void main() {
  const category = ForumCategory(
    name: '交流与讨论',
    boards: [
      ForumBoard(fid: 1, name: '逆向交流'),
      ForumBoard(fid: 2, name: '玩机交流'),
      ForumBoard(fid: 3, name: '编程开发'),
    ],
  );

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          // 真机上这里是「状态栏 + 顶栏」的高度，底部还有手势条。
          data: const MediaQueryData(
            size: Size(421, 933),
            padding: EdgeInsets.only(top: 100, bottom: 34),
          ),
          child: Material(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              children: const [BoardCategorySection(category: category)],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('分区标题到第一行卡片之间不留大空白', (tester) async {
    await pumpSection(tester);

    final header = tester.getRect(find.text('交流与讨论'));
    final firstTile = tester.getRect(find.text('逆向交流'));

    // 卡片高 70、文字在卡片里居中，正常间距在 26dp 上下；
    // 安全区被当成内边距时会变成 120dp 以上。
    expect(
      firstTile.top - header.bottom,
      lessThan(40),
      reason: '标题和卡片之间被撑开了，网格多半又吃了 MediaQuery 的安全区',
    );
  });

  testWidgets('分区内两行卡片之间只有 9dp 的间距', (tester) async {
    await pumpSection(tester);

    final first = tester.getRect(find.byType(InkWell).at(0));
    final second = tester.getRect(find.byType(InkWell).at(2));
    expect(second.top - first.bottom, 9);
    expect(first.height, 70);
  });
}
