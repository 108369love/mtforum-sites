import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/reply_context.dart';

/// 回复页上的隐藏域解析。
///
/// 这段 HTML 取自 Discuz X3.5 `template/default/touch/forum/post.htm`：
///
/// ```html
/// <input type="hidden" name="noticeauthor" value="$noticeauthor" />
/// <input type="hidden" name="noticetrimstr" value="$noticetrimstr" />
/// <input type="hidden" name="noticeauthormsg" value="$noticeauthormsg" />
/// ```
void main() {
  const replyPage = '''
<form method="post" id="postform" action="forum.php?mod=post&action=reply&fid=41&tid=175647&repquote=9944123">
<input type="hidden" name="formhash" value="35cecc51" />
<input type="hidden" name="noticeauthor" value="d3V5X2E%3DAbCdEf" />
<input type="hidden" name="noticetrimstr" value="[quote][color=#999999]Aioprh 发表于 2026-10-29 00:57[/color]&#10;[color=#999999]这个布局的图标怎么跟我之前开源的一样[/color][/quote]" />
<input type="hidden" name="noticeauthormsg" value="这个布局的图标怎么跟我之前开源的一样" />
<textarea name="message"></textarea>
</form>
''';

  test('取到服务端算好的引用条与提醒凭证', () {
    final ctx = ReplyContext.fromHtml(replyPage);
    expect(ctx.formhash, '35cecc51');
    expect(ctx.noticeAuthor, 'd3V5X2E%3DAbCdEf');
    expect(ctx.noticeTrim, startsWith('[quote]'));
    expect(ctx.noticeTrim, endsWith('[/quote]'));
    // &#10; 还原成换行，引用条才是两行。
    expect(ctx.noticeTrim, contains('\n'));
    expect(ctx.noticeTrim, contains('Aioprh 发表于 2026-10-29 00:57'));
    expect(ctx.noticeAuthorMsg, '这个布局的图标怎么跟我之前开源的一样');
    expect(ctx.isEmpty, isFalse);
  });

  test('属性顺序、单引号、无引号都能认', () {
    const html = '''
<input value='第一' type=hidden name=noticetrimstr>
<input name="noticeauthor" type="hidden" value="abc">
''';
    final ctx = ReplyContext.fromHtml(html);
    expect(ctx.noticeTrim, '第一');
    expect(ctx.noticeAuthor, 'abc');
  });

  test('实体还原：链接里的 &amp; 要变回 &', () {
    const html =
        '<input type="hidden" name="noticetrimstr" value="[url=forum.php?mod=redirect&amp;goto=findpost&amp;pid=1]x[/url]">';
    expect(
      ReplyContext.fromHtml(html).noticeTrim,
      '[url=forum.php?mod=redirect&goto=findpost&pid=1]x[/url]',
    );
  });

  test('formhash 不会被当成引用条', () {
    const html = '<input type="hidden" name="formhash" value="35cecc51">';
    final ctx = ReplyContext.fromHtml(html);
    expect(ctx.formhash, '35cecc51');
    expect(ctx.noticeTrim, isEmpty);
    expect(ctx.isEmpty, isTrue);
  });

  test('不是回复页时返回空上下文，不抛异常', () {
    expect(ReplyContext.fromHtml('').isEmpty, isTrue);
    expect(ReplyContext.fromHtml('<div>普通页面</div>').isEmpty, isTrue);
    expect(ReplyContext.empty.isEmpty, isTrue);
  });
}
