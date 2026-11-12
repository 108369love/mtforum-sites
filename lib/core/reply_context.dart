/// 回复页上由服务端现算的「引用条」凭证。
///
/// 手机版网页点某一楼的「回复」，跳到的是
/// `forum.php?mod=post&action=reply&…&repquote=<pid>`，那一页里有三个隐藏域：
///
/// ```html
/// <input type="hidden" name="noticeauthor" value="…" />
/// <input type="hidden" name="noticetrimstr" value="[quote]…[/quote]" />
/// <input type="hidden" name="noticeauthormsg" value="…" />
/// ```
///
/// 提交时服务端在 `model_forum_post` 里做两件事：
///
/// ```php
/// if(!empty($this->param['noticetrimstr'])) {
///     $this->param['message'] = $this->param['noticetrimstr']."\n\n".$this->param['message'];
/// }
/// ```
///
/// 也就是说：**回复长什么样，取决于提交时带上去的 `noticetrimstr`**。
/// 带上了，正文开头就有一段网页端那种灰色引用框（作者 + 时间 + 原文前几行），
/// 一眼能看出回复的是哪一层；没带，就是一条光秃秃的独立回复。
///
/// 这两个值都含 `authcode()` 加密，密钥是站点 `authkey`，客户端推不出来，
/// 只能从回复页里原样取回来再用。
library;

class ReplyContext {
  const ReplyContext({
    this.formhash = '',
    this.noticeAuthor = '',
    this.noticeTrim = '',
    this.noticeAuthorMsg = '',
  });

  /// 回复表单用的 formhash（页面里没有时为空）。
  final String formhash;

  /// `authcode('q|作者uid')`：服务端靠它给对方发「回复了您的帖子」提醒。
  final String noticeAuthor;

  /// 服务端拼好的 `[quote]…[/quote]`，和网页端发出来的一模一样。
  final String noticeTrim;

  /// 提醒内容里引用的原文摘要。
  final String noticeAuthorMsg;

  static const ReplyContext empty = ReplyContext();

  bool get isEmpty => noticeAuthor.isEmpty && noticeTrim.isEmpty;

  factory ReplyContext.fromHtml(String html) => ReplyContext(
    formhash: inputValue(html, 'formhash'),
    noticeAuthor: inputValue(html, 'noticeauthor'),
    noticeTrim: inputValue(html, 'noticetrimstr'),
    noticeAuthorMsg: inputValue(html, 'noticeauthormsg'),
  );
}

final RegExp _inputTag = RegExp(r'<input\b[^>]*>', caseSensitive: false);

/// 取 `<input name="…" value="…">` 的值；属性顺序、单双引号都能认。
String inputValue(String html, String name) {
  if (html.isEmpty) return '';
  for (final match in _inputTag.allMatches(html)) {
    final tag = match.group(0)!;
    if (attributeValue(tag, 'name')?.toLowerCase() != name.toLowerCase()) continue;
    return decodeEntities(attributeValue(tag, 'value') ?? '');
  }
  return '';
}

/// 取标签里某个属性的值，去掉包裹的引号。
String? attributeValue(String tag, String name) {
  final pattern = RegExp(
    '(?:^|\\s)${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(tag);
  if (match == null) return null;
  return match.group(1) ?? match.group(2) ?? match.group(3) ?? '';
}

const Map<String, String> _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'ldquo': '“',
  'rdquo': '”',
  'hellip': '…',
};

/// 还原隐藏域里的 HTML 实体：`&amp;` 不还原的话，引用里的链接会带上 `&amp;`。
String decodeEntities(String text) {
  if (!text.contains('&')) return text;
  return text.replaceAllMapped(
    RegExp(r'&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z]+);'),
    (match) {
      final body = match.group(1)!;
      if (body.startsWith('#')) {
        final hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
        final code = int.tryParse(body.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
        if (code == null || code <= 0 || code > 0x10FFFF) return match.group(0)!;
        return String.fromCharCode(code);
      }
      return _namedEntities[body.toLowerCase()] ?? match.group(0)!;
    },
  );
}
