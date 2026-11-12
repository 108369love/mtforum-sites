import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:mt_forum/data/forum_repository.dart';

/// 点赞回执与「是否已赞」的判定。
///
/// 线上问题是：赞成功却提示「点赞失败」，而且之后再点也取消不了——因为失败
/// 分支没有置位本地状态，下一次仍然发 add。这里把两个判据钉住。
void main() {
  group('点赞回执', () {
    test('站点没给文案也算成功', () {
      // 有的模板只回一段 script，CDATA 里没有中文，取出来是空串。
      expect(ForumRepository.recommendFailure(''), isNull);
    });

    test('各种成功文案都不能误判成失败', () {
      for (final message in <String>[
        '感谢您的参与，现在将转入主题页',
        '点赞成功',
        '操作成功',
        '评价成功',
        '取消成功',
        '已取消',
        '谢谢参与',
      ]) {
        expect(ForumRepository.recommendFailure(message), isNull, reason: message);
      }
    });

    test('已评价过要给出「已经赞过」而不是通用失败', () {
      expect(ForumRepository.recommendFailure('您已评价过本主题'), '你已经赞过这个帖子');
      expect(ForumRepository.recommendFailure('抱歉，您已经评价过'), '你已经赞过这个帖子');
      expect(ForumRepository.recommendFailure('您已经赞过该帖'), '你已经赞过这个帖子');
    });

    test('踩的重复提示用踩的措辞', () {
      expect(
        ForumRepository.recommendFailure('您已评价过本主题', up: false),
        '你已经踩过这个帖子',
      );
    });

    test('取消时服务端说没评价过，要能被识别', () {
      expect(ForumRepository.recommendFailure('您还没有评价过本主题'), '你还没有点赞');
    });

    test('其余明确失败仍然拦得住', () {
      expect(ForumRepository.recommendFailure('不能评价自己的帖子'), '不能点赞自己的帖子');
      expect(ForumRepository.recommendFailure('该主题已关闭'), '该主题已关闭，无法点赞');
      expect(ForumRepository.recommendFailure('今日评价机会已用完'), '今天的点赞次数已用完');
      expect(ForumRepository.recommendFailure('非法操作'), isNotNull);
      expect(ForumRepository.recommendFailure('您没有权限进行此操作'), isNotNull);
    });

    test('取消遇到没见过的提示要暴露出来，不能静默当成功', () {
      // 站点不认取消动作时常常回 200 + 一句没见过的提示，宽松放行会让界面
      // 显示已取消、服务端却仍然赞着。
      expect(ForumRepository.recommendFailure('系统繁忙，请稍后再试', up: false), contains('取消失败'));
      expect(ForumRepository.recommendFailure('请求来路不正确，请刷新页面', up: false), '站点校验未通过，请重试');
      expect(ForumRepository.recommendFailure('未定义操作', up: false), '站点不支持取消点赞');
    });

    test('真正的取消成功不会被误判', () {
      for (final message in <String>['取消成功', '已取消', '操作成功', '操作完成']) {
        expect(ForumRepository.recommendFailure(message, up: false), isNull, reason: message);
      }
    });
  });

  group('从页面判断是否已赞', () {
    test('按钮带 f_a 激活类', () {
      final doc = html_parser.parse(
        '<a class="comiis_recommend_a_color f_a" href="forum.php?mod=misc&amp;action=recommend&amp;do=add&amp;tid=1">赞</a>',
      );
      expect(ForumRepository.threadLiked(doc), isTrue);
    });

    test('按钮已换成 do=cancel', () {
      final doc = html_parser.parse(
        '<a class="comiis_recommend_a_color" '
        'href="forum.php?mod=misc&action=recommend&do=cancel&tid=1">取消</a>',
      );
      expect(ForumRepository.threadLiked(doc), isTrue);
    });

    test('按钮换成 cancel=1 也算已赞', () {
      final doc = html_parser.parse(
        '<a class="comiis_recommend_a_color" '
        'href="forum.php?mod=misc&action=recommend&do=add&tid=1&cancel=1">赞</a>',
      );
      expect(ForumRepository.threadLiked(doc), isTrue);
    });

    test('真实结构：数字是独立节点，按钮在它前面', () {
      // Discuz 原生模板里 #recommendv_add 只是数字，不是按钮。以前拿它判激活
      // 态，等于一直在看一个 span 的 class，永远读不到「已赞」。
      final doc = html_parser.parse(
        '<span id="recommendv">'
        '<a class="comiis_recommend_a_color" '
        'href="forum.php?mod=misc&action=recommend&do=add&tid=1&hash=abc">赞</a>'
        '<span id="recommendv_add">3</span>'
        '</span>',
      );
      expect(ForumRepository.threadLiked(doc), isFalse);
      expect(ForumRepository.recommendHref(doc), contains('do=add'));
    });

    test('踩的链接不会被当成赞', () {
      final doc = html_parser.parse(
        '<a href="forum.php?mod=misc&action=recommend&do=subtract&tid=1">踩</a>'
        '<a class="comiis_recommend_a_color" '
        'href="forum.php?mod=misc&action=recommend&do=add&tid=1">赞</a>',
      );
      expect(ForumRepository.recommendHref(doc), contains('do=add'));
      expect(ForumRepository.threadLiked(doc), isFalse);
    });

    test('页面里没有点赞按钮（游客）', () {
      expect(ForumRepository.threadLiked(html_parser.parse('<div>请登录</div>')), isFalse);
    });
  });

    test('克米模板：点赞图标 f_a 就是已赞', () {
      // 站点在用的手机模板，底栏那颗赞长这样。它既不是链接、也不叫
      // comiis_recommend_a_color，取消后图标换成 f_b。之前只按旧两条找，
      // 进帖子永远显示未赞，点一下发 add，服务端回「已评价过」，取消更没门。
      const liked = '<li><a href="javascript:;" class="comiis_recommend_addkey comiis_recommend_new">'
          '<i class="comiis_font comiis_recommend_color f_a">&#xe63b;</i>'
          '<span class="bg_del f_f comiis_kmvnum comiis_recommend_num" id="comiis_recommend_num">2</span>'
          '</a></li>';
      expect(ForumRepository.threadLiked(html_parser.parse(liked)), isTrue);

      const unliked = '<li><a href="javascript:;" class="comiis_recommend_addkey comiis_recommend_new">'
          '<i class="comiis_font comiis_recommend_color f_b">&#xe63b;</i>'
          '<span class="bg_del f_f comiis_kmvnum comiis_recommend_num" id="comiis_recommend_num">2</span>'
          '</a></li>';
      expect(ForumRepository.threadLiked(html_parser.parse(unliked)), isFalse);
    });

    test('收藏的 f_a 不会被当成点赞', () {
      final doc = html_parser.parse(
        '<a href="javascript:;" id="comiis_favorite_a">'
        '<i class="comiis_favorite_a_color comiis_font f_a">&#xe617;</i></a>'
        '<i class="comiis_font comiis_recommend_color f_b">&#xe63b;</i>',
      );
      expect(ForumRepository.threadLiked(doc), isFalse);
    });
}
