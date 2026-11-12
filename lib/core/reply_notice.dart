/// 「回复某楼」时贴在正文最前面的引用条。
///
/// 手机版网页点某一楼的「回复」，实际提交的是 `repquote=<pid>`，
/// 服务端在 `post_newreply.php` 里把这一层的信息拼成：
///
/// ```php
/// $post_reply_quote = '{作者} 发表于 {时间}';
/// $message = "[quote][color=#999999]{$post_reply_quote}[/color]\n"
///          . "[color=#999999]{$message}[/color][/quote]";   // 移动端
/// ```
///
/// 这段由站点按 `authkey` 现算，客户端拼不出来格式完全相同的那份，
/// 正常路径从回复页的 `noticetrimstr` 隐藏域原样取（见 `reply_context.dart`）。
/// 只有取不到时才用这里的兜底格式——样式对齐网页端，只是作者名换成链接，
/// 点一下能跳到被回复的楼层。
///
/// 注意 `reppost` 那条路只发提醒、不动正文，发出来就是一条独立回复，
/// 所以回复某楼不要只带 `reppost`。
library;

/// `[quote]` 的开头部分（作者 + 时间，带楼层链接）。
String buildQuoteHeader({
  required String author,
  required String time,
  required int pid,
  required int tid,
}) {
  final name = author.trim().isEmpty ? '该楼' : author.trim();
  final at = time.trim();
  final label = at.isEmpty ? name : '$name 发表于 $at';
  return '[quote][size=2]'
      '[url=forum.php?mod=redirect&goto=findpost&pid=$pid&ptid=$tid]'
      '[color=#999999]$label[/color][/url][/size]';
}

/// 只有抬头、不带原文的完整引用块（兜底用）。
String buildReplyNotice({
  required String author,
  String time = '',
  required int pid,
  required int tid,
}) {
  return '${buildQuoteHeader(author: author, time: time, pid: pid, tid: tid)}[/quote]';
}
