/// 回收站主题的识别规则。
///
/// Discuz 删除主题时不会真的抹掉记录：开了回收站的版块会把
/// `displayorder` 改成 -1，主题留在原版块里，只是普通用户点进去看到
/// 的是「主题不存在或已被删除」。
///
/// 这类主题在列表里仍然占一个位置，各模板的标记方式不一样：
///
/// - 桌面模板给标题链接加 `class="recy"`（配合 `.recy { line-through }`）；
/// - 手机模板干脆在标题前面拼一个「回收站」标签，
///   于是标题就长成「回收站【更新】mt论坛_1.8.8」；
/// - 也有的模板单独放一个 `<span class="xg1">回收站</span>` 小标签。
///
/// 用户自己删掉的帖子都会进这里，列表里留着除了占位置没有任何用处。
class RecycleBin {
  const RecycleBin._();

  /// 标签文字，模板直接用这个原文。
  static const String label = '回收站';

  /// 带括号的完整前缀写法。
  static const List<String> _wrappedPrefixes = [
    '[回收站]',
    '【回收站】',
    '（回收站）',
    '(回收站)',
  ];

  /// 「回收站」后面允许紧跟的字符：括号或空白。
  ///
  /// 只认这些是为了不误伤「回收站使用说明」这类正常标题——
  /// 真正的已删除主题，模板拼的是标签 + 原标题，中间必然是括号或空格。
  static const String _followers = ' \u3000【[「《（(<【';

  /// 标题是否带回收站前缀。
  static bool hasTitlePrefix(String title) {
    final text = title.trim();
    if (text.isEmpty) return false;
    for (final wrapped in _wrappedPrefixes) {
      if (text.startsWith(wrapped)) return true;
    }
    if (!text.startsWith(label) || text.length <= label.length) return false;
    return _followers.contains(text[label.length]);
  }

  /// 把标题上的回收站前缀剥掉，剩下真正的内容。
  ///
  /// 目前列表里直接跳过整条，这个留着给「想保留但去掉标签」的场景用。
  static String stripTitlePrefix(String title) {
    final text = title.trim();
    for (final wrapped in _wrappedPrefixes) {
      if (text.startsWith(wrapped)) return text.substring(wrapped.length).trim();
    }
    if (hasTitlePrefix(text)) return text.substring(label.length).trim();
    return text;
  }

  /// Discuz 桌面模板用 `class="recy"` 标已删除。
  static bool hasRecyClass(Iterable<String> classes) => classes.contains('recy');

  /// 列表项里的「回收站」小标签。
  static bool isLabel(String text) => text.trim() == label;
}
