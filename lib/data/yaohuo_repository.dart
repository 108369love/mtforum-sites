import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/yaohuo_session.dart';

/// 妖火网要求登录时抛这个，UI 据此弹出登录入口。
class YaohuoNotLoggedIn implements Exception {
  const YaohuoNotLoggedIn();
}

/// 帖子列表里的一条。
class YaohuoThreadItem {
  const YaohuoThreadItem({
    required this.title,
    required this.url,
    required this.author,
    required this.reply,
    required this.read,
    required this.time,
  });

  final String title;
  final String url;
  final String author;
  final String reply;
  final String read;
  final String time;
}

/// 一条楼中回复。
class YaohuoReply {
  const YaohuoReply({
    required this.floor,
    required this.author,
    required this.content,
    required this.time,
  });

  final String floor;
  final String author;
  final String content;
  final String time;
}

/// 帖子详情（正文 + 回复）。
class YaohuoThread {
  const YaohuoThread({
    required this.title,
    required this.board,
    required this.author,
    required this.time,
    required this.reads,
    required this.bodyText,
    required this.images,
    required this.links,
    required this.replies,
    required this.moreUrl,
  });

  final String title;
  final String board;
  final String author;
  final String time;
  final String reads;
  final String bodyText;
  final List<String> images;
  final List<({String text, String url})> links;
  final List<YaohuoReply> replies;

  /// 「更多回帖」的地址，空串表示没有更多。
  final String moreUrl;
}

/// 妖火网的原生数据层。
///
/// 页面结构（2026-11 实测，参考同站开源客户端 Townwang/yaohuo 的 jsoup 选择器）：
/// - 列表项：`div.line1, div.line2`，首个 `a[href]` 是标题，移除后剩下的文本是
///   `作者 / 回复数 / 阅读数`，时间在 `span.right`；
/// - 详情：首个 `div.content` 里是 `[标题] … (阅N)` + `[时间] …`，正文在
///   `div.bbscontent`（用 `<!--listS-->…<!--listE-->` 包起来）；
/// - 楼主信息：`div.subtitle` 里带 `[楼主]` 的那一块；
/// - 回复：`div.recontent > div.reline`，`[楼层]` 开头，第二个 `<a>` 是用户名；
/// - 更多回复：`div.more > a`。
class YaohuoRepository {
  YaohuoRepository._();

  static final YaohuoRepository instance = YaohuoRepository._();

  static const String _base = 'https://yaohuo.me/';

  Future<String> _fetch(String url, {Map<String, String>? query}) async {
    await YaohuoSession.instance.refresh();
    var uri = Uri.parse(url.startsWith('http') ? url : _base + url.replaceFirst(RegExp('^/+'), ''));
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    final response = await http.get(
      uri,
      headers: {
        'User-Agent': AppConfig.userAgent,
        'Referer': _base,
        'Accept': 'text/html,application/xhtml+xml',
        if (YaohuoSession.instance.cookieHeader.isNotEmpty) 'Cookie': YaohuoSession.instance.cookieHeader,
      },
    ).timeout(const Duration(seconds: 25));
    final body = _decode(response);
    if (response.statusCode >= 400) {
      throw StateError('HTTP ${response.statusCode}');
    }
    if (body.contains('请先登录') || body.contains('请先登录网站')) {
      throw const YaohuoNotLoggedIn();
    }
    return body;
  }

  String _decode(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(response.bodyBytes, allowInvalid: true);
    }
  }

  /// 最新帖子列表（妖火首页的「新帖」）。
  Future<List<YaohuoThreadItem>> fetchNewThreads({int page = 1}) async {
    final html = await _fetch(
      'bbs/book_list.aspx',
      query: {'action': 'new', 'getTotal': '2021', 'page': '$page', 'siteId': '1000', 'classId': '0'},
    );
    return parseThreadList(html);
  }

  /// 板块列表。
  Future<List<YaohuoThreadItem>> fetchBoardThreads({required int classId, int page = 1}) async {
    final html = await _fetch(
      'bbs/book_list.aspx',
      query: {'action': 'class', 'classId': '$classId', 'page': '$page', 'siteId': '1000', 'getTotal': '2021'},
    );
    return parseThreadList(html);
  }

  Future<YaohuoThread> fetchThread(String url) async {
    final html = await _fetch(url);
    return parseThread(html, url);
  }

  /// 追加更多回复：返回这一页的回复和「下一页」地址。
  Future<({List<YaohuoReply> replies, String moreUrl})> fetchReplyPage(String url) async {
    final html = await _fetch(url);
    final doc = html_parser.parse(html);
    final more = doc.querySelector('div.more a')?.attributes['href'] ?? '';
    return (
      replies: _parseReplies(doc),
      moreUrl: more.isEmpty ? '' : _absolute(more),
    );
  }

  // ---------------------------------------------------------------- 解析

  static List<YaohuoThreadItem> parseThreadList(String html) {
    final doc = html_parser.parse(html);
    final items = <YaohuoThreadItem>[];
    for (final element in doc.querySelectorAll('div.line1, div.line2')) {
      final anchor = element.querySelector('a[href]');
      if (anchor == null) continue;
      final href = anchor.attributes['href'] ?? '';
      final title = anchor.text.trim();
      if (href.isEmpty || title.isEmpty) continue;
      final time = element.querySelector('span.right')?.text.trim() ?? '';
      // 去掉标题链接之后，剩下的文本才是「作者 / 回复 / 阅读」。
      anchor.remove();
      final parts = element.text.split('/');
      final author = parts[0].trim().split(' ').last;
      final reply = parts.length > 1 ? parts[1].trim() : '';
      final read = parts.length > 2 ? parts[2].trim() : '';
      items.add(YaohuoThreadItem(
        title: title,
        url: _absolute(href),
        author: author,
        reply: reply,
        read: read,
        time: time,
      ));
    }
    return items;
  }

  static YaohuoThread parseThread(String html, String url) {
    final doc = html_parser.parse(html);
    final contents = doc.querySelectorAll('div.content');
    final head = contents.isEmpty ? null : contents.first;
    final headText = head?.text ?? '';

    var title = _firstMatch(headText, RegExp(r'\[标题\]\s*([^\n]+)')) ?? '';
    title = title.replaceAll(RegExp(r'\s*\(阅\d+\)\s*$'), '').trim();
    if (title.isEmpty) {
      title = doc.querySelector('title')?.text.trim() ?? '帖子';
    }
    final time = (_firstMatch(headText, RegExp(r'\[时间\]\s*([^\n]+)')) ?? '').trim();
    final reads = _firstMatch(headText, RegExp(r'\(阅(\d+)\)')) ?? '';

    final board = _parseBoard(doc);
    final author = _parseAuthor(doc);

    final bodyHtml = head?.querySelector('div.bbscontent')?.innerHtml ?? '';
    final cleaned = bodyHtml
        .replaceAll('<!--listS-->', '')
        .replaceAll('<!--listE-->', '')
        .replaceAll(RegExp(r'<span id="KL_show_next_list"></span>'), '');
    final fragment = html_parser.parseFragment(cleaned);
    final bodyText = _compact(fragment.text ?? '');
    final images = <String>[];
    for (final img in fragment.querySelectorAll('img')) {
      final src = img.attributes['src'] ?? '';
      if (src.isEmpty) continue;
      if (images.contains(src)) continue;
      images.add(_absolute(src));
    }
    final links = <({String text, String url})>[];
    for (final anchor in fragment.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      final text = anchor.text.trim();
      if (href.isEmpty || text.isEmpty) continue;
      links.add((text: text, url: _absolute(href)));
    }

    final more = doc.querySelector('div.more a')?.attributes['href'] ?? '';

    return YaohuoThread(
      title: title,
      board: board,
      author: author,
      time: time,
      reads: reads,
      bodyText: bodyText,
      images: images,
      links: links,
      replies: _parseReplies(doc),
      moreUrl: more.isEmpty ? '' : _absolute(more),
    );
  }

  static List<YaohuoReply> _parseReplies(dom.Document doc) {
    final replies = <YaohuoReply>[];
    for (final element in doc.querySelectorAll('div.recontent div.reline')) {
      final text = element.text.trim();
      if (text.isEmpty) continue;
      final floor = _firstMatch(text, RegExp(r'^\[([^\]]+)\]')) ?? '';
      final anchors = element.querySelectorAll('a');
      // 第一个 a 是「回」，第二个才是用户名。
      final author = anchors.length > 1 ? anchors[1].text.trim() : '';
      final colon = text.indexOf('：');
      var content = colon >= 0 ? text.substring(colon + 1) : text;
      var when = '';
      final timeMatch = RegExp(r'\((\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2})\)\s*$').firstMatch(content);
      if (timeMatch != null) {
        when = timeMatch.group(1) ?? '';
        content = content.substring(0, timeMatch.start);
      }
      replies.add(YaohuoReply(
        floor: floor,
        author: author,
        content: _compact(content),
        time: when,
      ));
    }
    return replies;
  }

  static String _parseBoard(dom.Document doc) {
    final breadcrumb = doc.querySelector('div.title')?.text ?? '';
    final segments = breadcrumb.split(RegExp(r'[>＞]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2) return segments[segments.length - 2];
    return '';
  }

  static String _parseAuthor(dom.Document doc) {
    for (final subtitle in doc.querySelectorAll('div.subtitle')) {
      if (!subtitle.text.contains('[楼主]')) continue;
      final anchor = subtitle.querySelector('a[href]');
      final name = anchor?.text.trim() ?? '';
      return name.replaceAll(RegExp(r'\([^)]*\)\s*$'), '').trim();
    }
    return '';
  }

  static String? _firstMatch(String text, RegExp pattern) => pattern.firstMatch(text)?.group(1);

  static String _compact(String text) => text
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  static String _absolute(String href) {
    if (href.startsWith('http://') || href.startsWith('https://')) return href;
    return Uri.parse(_base).resolve(href.startsWith('/') ? href.substring(1) : href).toString();
  }
}
