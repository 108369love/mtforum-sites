import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/models.dart';
import 'package:mt_forum/state/app_state.dart';
import 'package:mt_forum/ui/pages/thread_page.dart';
import 'package:mt_forum/ui/widgets/glass_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 帖子页的版式契约：顶栏、边距、楼层卡片、楼中楼底板、翻页条。
///
/// 这几处都是「看起来只是差几个 dp、叠在一起就别扭」的地方，靠肉眼回归
/// 很容易漏，写成断言盯着。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.threadGlassOpacity = 0.55;
    AppState.instance.threadGlassBlur = 22;
  });

  ForumPost opPost({int likes = 26}) => ForumPost(
        pid: 1,
        uid: 12,
        author: 'Binary_涛',
        avatar: '',
        time: '2026-10-28 20:14',
        html: '<p>主题正文。</p>',
        floor: 1,
        level: 'Lv.7',
        isOp: true,
        likes: likes,
      );

  ForumPost reply(int pid, int floor, {List<ForumComment> comments = const []}) => ForumPost(
        pid: pid,
        uid: 30 + pid,
        author: '回复者$pid',
        avatar: '',
        time: '2026-10-28 21:0$pid',
        html: '<p>第 $floor 楼的内容。</p>',
        floor: floor,
        level: 'Lv.3',
        comments: comments,
      );

  ThreadDetail detailOf(List<ForumPost> posts, {bool hasMore = true}) => ThreadDetail(
        tid: 1,
        title: '把玻璃效果铺满整个客户端之后，我踩过的几个坑',
        fid: 3,
        boardName: '版本发布',
        author: 'Binary_涛',
        time: '2026-10-28 20:14',
        views: 4821,
        replies: 93,
        posts: posts,
        formhash: 'x',
        hasMore: hasMore,
        isLoggedIn: true,
        likes: 26,
        dislikes: 1,
        uid: 12,
      );

  Future<void> pump(WidgetTester tester, ThreadDetail detail) async {
    tester.view.physicalSize = const Size(1264, 2800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ThreadPage.preview(detail: detail, posts: detail.posts)),
    );
    await tester.pump();
  }

  testWidgets('顶栏走统一的玻璃组件，正文从它背后滚过', (tester) async {
    await pump(tester, detailOf([opPost(), reply(2, 2)]));

    expect(find.byType(GlassAppBar), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.extendBodyBehindAppBar, isTrue);
  });

  testWidgets('顶栏标题比正文大标题小，两个标题不抢主次', (tester) async {
    final detail = detailOf([opPost(), reply(2, 2)]);
    await pump(tester, detail);

    final appBarTitle = tester.widget<Text>(
      find.descendant(of: find.byType(GlassAppBar), matching: find.text(detail.title)),
    );
    // 顶栏和正文各有一份同名标题，按容器区分开。
    final pageTitle = tester.widget<Text>(
      find.descendant(of: find.byType(ListView), matching: find.text(detail.title)),
    );

    expect(appBarTitle.style?.fontSize, lessThan(pageTitle.style!.fontSize!));
    expect(appBarTitle.style?.fontSize, lessThanOrEqualTo(17));
  });

  testWidgets('楼层列表左右边距跟全站一致', (tester) async {
    await pump(tester, detailOf([opPost(), reply(2, 2)]));

    final list = tester.widget<ListView>(find.byType(ListView).first);
    final padding = list.padding as EdgeInsets;
    expect(padding.left, kPageGutter);
    expect(padding.right, kPageGutter);
  });

  testWidgets('楼层卡片统一圆角，主体和回复不再一个 16 一个 12', (tester) async {
    await pump(tester, detailOf([opPost(), reply(2, 2)]));

    final cards = tester.widgetList<Card>(find.byType(Card)).toList();
    expect(cards, isNotEmpty);
    for (final card in cards) {
      final shape = card.shape! as RoundedRectangleBorder;
      expect((shape.borderRadius as BorderRadius).topLeft.x, 14);
    }
  });

  testWidgets('回复框去掉了主题自带的下划线', (tester) async {
    await pump(tester, detailOf([opPost(), reply(2, 2)]));

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.decoration?.border, InputBorder.none);
    expect(field.decoration?.enabledBorder, InputBorder.none);
    expect(field.decoration?.focusedBorder, InputBorder.none);
  });

  testWidgets('楼中楼底板撑满卡片宽度，不随点评长短收缩', (tester) async {
    await pump(
      tester,
      detailOf([
        opPost(),
        reply(2, 2, comments: const [
          ForumComment(author: 'Binary_涛', time: '21:10', text: '谢'),
        ]),
      ]),
    );

    // Divider 内部也是 Container 且带 infinity 约束，用圆角把楼中楼底板挑出来。
    final boxes = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.constraints?.maxWidth == double.infinity &&
          (w.decoration as BoxDecoration?)?.borderRadius == BorderRadius.circular(12),
    );
    expect(boxes, findsOneWidget, reason: '楼中楼底板是唯一要显式撑满的容器');

    final card = tester.widget<Card>(find.byType(Card).last);
    final shape = card.shape! as RoundedRectangleBorder;
    expect(shape.side.width, lessThan(1), reason: '普通楼层是发丝描边');

    final boxWidth = tester.getSize(boxes).width;
    final cardWidth = tester.getSize(find.byType(Card).last).width;
    // 卡片内边距 14 * 2，底板应当贴着内容区两侧。
    expect(boxWidth, closeTo(cardWidth - 28, 1));
  });

  testWidgets('翻页条：首页不能上一页，还有更多时下一页可点', (tester) async {
    await pump(tester, detailOf([opPost(), reply(2, 2)], hasMore: true));

    expect(find.text('第 1 页'), findsOneWidget);
    expect(find.text('还有更多回复'), findsOneWidget);

    InkWell tapOf(String label) => tester.widget<InkWell>(
          find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
        );

    expect(tapOf('上一页').onTap, isNull, reason: '第 1 页没有上一页');
    expect(tapOf('下一页').onTap, isNotNull);
  });

  testWidgets('翻页条：没有更多时右侧变成「到底了」且不可点', (tester) async {
    await pump(tester, detailOf([opPost()], hasMore: false));

    expect(find.text('到底了'), findsOneWidget);
    expect(find.text('已显示全部内容'), findsOneWidget);
    final more = tester.widget<InkWell>(
      find.ancestor(of: find.text('到底了'), matching: find.byType(InkWell)).first,
    );
    expect(more.onTap, isNull);
  });
}
