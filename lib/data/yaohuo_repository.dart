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

/// 帖子详情（正文 + 回复 + 可执行动作）。
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
    this.threadId = '',
    this.classId = '',
    this.sid = '',
    this.favoriteUrl = '',
    this.upUrl = '',
    this.likeUrl = '',
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

  /// 回帖表单需要的隐藏字段（站点用 sid 当一次性令牌）。
  final String threadId;
  final String classId;
  final String sid;

  /// 收藏 / 顶 / 赞 的地址。
  final String favoriteUrl;
  final String upUrl;
  final String likeUrl;
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
/// - 更多回复：`div.more > a`；
/// - 回帖：`form[name=f]` 的隐藏字段（id / classid / sid）+ POST `bbs/book_re.aspx`。
class YaohuoRepository {
  YaohuoRepository._();

  static final YaohuoRepository instance = YaohuoRepository._();

  static const String _base = 'https://yaohuo.me/';

  static const String actionNew = 'new';
  static const String actionGood = 'good';
  static const String actionClass = 'class';
  static const String actionSearch = 'search';

  /// 妖火的板块（classid → 名字），取自站点自身的板块入口。
  static const List<({int id, String name})> boards = <({int id, String name})>[
    (id: 201, name: '资源共享'),
    (id: 197, name: '综合技术'),
    (id: 203, name: '免流讨论'),
    (id: 204, name: '有奖活动'),
    (id: 177, name: '妖火茶馆'),
    (id: 213, name: '悬赏问答'),
    (id: 240, name: '贴图晒照'),
    (id: 199, name: '站务处理'),
    (id: 198, name: '投诉建议'),
  ];

  Map<String, String> get _headers => <String, String>{
        'User-Agent': AppConfig.userAgent,
        'Referer': _base,
        'Accept': 'text/html,application/xhtml+xml',
        if (YaohuoSession.instance.cookieHeader.isNotEmpty) 'Cookie': YaohuoSession.instance.cookieHeader,
      };

  Future<String> _fetch(String url, {Map<String, String>? query}) async {
    await YaohuoSession.instance.refresh();
    var uri = Uri.parse(url.startsWith('http') ? url : _base + url.replaceFirst(RegExp(r'^/+'), ''));
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: <String, String>{...uri.queryParameters, ...query});
    }
    final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 25));
    final body = _decode(response);
    if (response.statusCode >= 400) {
      throw StateError('HTTP ${response.statusCode}');
    }
    if (_looksLoggedOut(body)) {
      throw const YaohuoNotLoggedIn();
    }
    return body;
  }

  bool _looksLoggedOut(String body) => body.contains('请先登录');

  String _decode(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(response.bodyBytes, allowInvalid: true);
    }
  }

  Future<List<YaohuoThreadItem>> fetchThreads({
    required String action,
    int classId = 0,
    int page = 1,
    String? key,
  }) async {
    final query = <String, String>{
      'action': action,
      'getTotal': '2021',
      'page': '$page',
      'siteId': '1000',
      if (action == actionSearch) ...<String, String>{
        'key': key ?? '',
        'type': 'title',
      } else
        'classId': '$classId',
    };
    final html = await _fetch('bbs/book_list.aspx', query: query);
    return parseThreadList(html);
  }

  /// 「我的地盘 / 空间 / 帖子 / 信箱」这几个入口的真实地址。
  ///
  /// 地址里带用户自己的 id，只能从登录后的首页导航里现取；取不到就退回站点
  /// 的固定路径（帖子/信箱），至少不会给个死链。
  Future<List<({String label, String url})>> fetchMyNav() async {
    const labels = <String>['我的地盘', '空间', '帖子', '信箱'];
    const fallback = <String, String>{
      '我的地盘': 'wapindex.aspx?siteid=1000',
      '空间': 'bbs/userinfo.aspx',
      '帖子': 'bbs/book_list.aspx?action=my',
      '信箱': 'bbs/messagelist.aspx?siteid=1000',
    };
    final found = <String, String>{};
    try {
      final html = await _fetch('wapindex.aspx?siteid=1000');
      final doc = html_parser.parse(html);
      for (final anchor in doc.querySelectorAll('a[href]')) {
        final text = anchor.text.trim();
        if (text.isEmpty) continue;
        for (final label in labels) {
          if (found.containsKey(label)) continue;
          if (text == label || text.startsWith(label)) {
            final href = anchor.attributes['href'] ?? '';
            if (href.isNotEmpty) found[label] = _absolute(href);
          }
        }
      }
    } catch (_) {
      // 取不到就用兜底地址，入口本身不该因为一次请求失败而消失。
    }
    return <({String label, String url})>[
      for (final label in labels) (label: label, url: found[label] ?? _absolute(fallback[label]!)),
    ];
  }

  /// 直接抓一个地址、按帖子列表解析（「我的帖子」这类站点自己给的入口用）。
  Future<List<YaohuoThreadItem>> fetchThreadListFromUrl(String url, {int page = 1}) async {
    final html = await _fetch(_withPage(url, page));
    return parseThreadList(html);
  }

  /// 抓一个地址、按「链接列表」解析（站内信、关注这类没有统一结构的列表页）。
  Future<List<({String title, String url, String extra})>> fetchLinkList(String url) async {
    final html = await _fetch(url);
    return parseLinkList(html);
  }

  /// 抓一个没有固定结构的详情页（站内信之类）：取最长的一块正文 + 图片。
  Future<({String title, String body, List<String> images})> fetchGenericPage(String url) async {
    final html = await _fetch(url);
    final doc = html_parser.parse(html);
    final title = (doc.querySelector('div.title')?.text.trim().isNotEmpty ?? false)
        ? doc.querySelector('div.title')!.text.trim()
        : (doc.querySelector('title')?.text.trim() ?? '');
    dom.Element? best;
    var bestLength = 0;
    for (final candidate in doc.querySelectorAll('div.content')) {
      final length = candidate.text.trim().length;
      if (length > bestLength) {
        bestLength = length;
        best = candidate;
      }
    }
    if (best == null || bestLength < 40) {
      final body = doc.body;
      if (body != null && body.text.trim().length > bestLength) best = body;
    }
    final htmlBody = best?.innerHtml ?? '';
    final fragment = html_parser.parseFragment(htmlBody.replaceAll(RegExp(r'<script.*?</script>', caseSensitive: false, dotAll: true), ''));
    final images = <String>[];
    for (final img in fragment.querySelectorAll('img')) {
      final src = img.attributes['src'] ?? '';
      if (src.isEmpty || images.contains(src)) continue;
      images.add(_absolute(src));
    }
    return (title: title, body: _compact(fragment.text ?? ''), images: images);
  }

  /// 抓用户资料页，解析成「字段 → 值」。
  Future<Map<String, String>> fetchUserInfo(String url) async {
    final html = await _fetch(url);
    return parseUserInfo(html);
  }

  static String _withPage(String url, int page) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return uri.replace(queryParameters: <String, String>{...uri.queryParameters, 'page': '$page'}).toString();
  }

  /// 通用链接列表：优先按 `div.line1, div.line2` 拆，退而求其次扫所有站内链接。
  static List<({String title, String url, String extra})> parseLinkList(String html) {
    final doc = html_parser.parse(html);
    final rows = <({String title, String url, String extra})>[];
    for (final element in doc.querySelectorAll('div.line1, div.line2')) {
      final anchor = element.querySelector('a[href]');
      if (anchor == null) continue;
      final href = anchor.attributes['href'] ?? '';
      final title = anchor.text.trim();
      if (href.isEmpty || title.isEmpty) continue;
      final time = element.querySelector('span.right')?.text.trim() ?? '';
      anchor.remove();
      rows.add((title: title, url: _absolute(href), extra: time.isEmpty ? element.text.trim() : time));
    }
    if (rows.isNotEmpty) return rows;
    // 兜底：页面里的站内链接（排除导航类固定入口）。
    final seen = <String>{};
    for (final anchor in doc.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      final title = anchor.text.trim();
      if (href.isEmpty || title.isEmpty) continue;
      if (!href.contains('.aspx')) continue;
      if (href.contains('messagelist.aspx') || href.contains('wapindex.aspx')) continue;
      if (!seen.add(href)) continue;
      rows.add((title: title, url: _absolute(href), extra: ''));
      if (rows.length >= 60) break;
    }
    return rows;
  }

  /// 用户资料页：`【字段】：值` 一行一条。
  static Map<String, String> parseUserInfo(String html) {
    final doc = html_parser.parse(html);
    final content = doc.querySelector('div.content');
    final raw = (content?.innerHtml ?? html)
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    final text = html_parser.parseFragment(raw).text ?? raw;
    final info = <String, String>{};
    for (final line in const LineSplitter().convert(text)) {
      final match = RegExp(r'【([^】]{1,12})】\s*[:：]\s*(.*)').firstMatch(line.trim());
      if (match == null) continue;
      final key = match.group(1)?.trim() ?? '';
      var value = (match.group(2) ?? '').trim();
      value = value.replaceAll(RegExp(r'\s{2,}'), ' ');
      if (key.isEmpty || value.isEmpty) continue;
      info[key] = value;
    }
    if (info.isNotEmpty) return info;
    // 兜底一：普通「键：值」行（键不超过 8 个字、不带空格）。
    for (final line in const LineSplitter().convert(text)) {
      final row = line.trim();
      if (row.isEmpty || row.length > 80) continue;
      final match = RegExp(r'^([^\s:：]{1,8})\s*[:：]\s*(\S.*)$').firstMatch(row);
      if (match == null) continue;
      final key = match.group(1)?.trim() ?? '';
      final value = match.group(2)?.trim() ?? '';
      if (key.isEmpty || value.isEmpty) continue;
      info[key] = value;
    }
    if (info.isNotEmpty) return info;
    // 兜底二：表格两列。
    for (final row in doc.querySelectorAll('tr')) {
      final cells = row.querySelectorAll('td, th');
      if (cells.length < 2) continue;
      final key = cells[0].text.trim();
      final value = cells[1].text.trim();
      if (key.isEmpty || value.isEmpty || key.length > 12) continue;
      info[key] = value;
    }
    return info;
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
    return (replies: _parseReplies(doc), moreUrl: more.isEmpty ? '' : _absolute(more));
  }

  /// 回帖。返回站点给出的提示文本（成功/失败都回一个，UI 直接展示）。
  Future<String> reply({
    required YaohuoThread thread,
    required String content,
    required String referer,
  }) async {
    await YaohuoSession.instance.refresh();
    try {
      final response = await http
          .post(
            Uri.parse('https://yaohuo.me/bbs/book_re.aspx?siteid=1000&action=add&lpage=1'),
            headers: <String, String>{
              ..._headers,
              'Referer': referer,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: <String, String>{
              'content': content,
              'sendmsg': '1',
              'sendmsg2': '1',
              'sid': thread.sid,
              'id': thread.threadId,
              'classid': thread.classId,
            },
          )
          .timeout(const Duration(seconds: 25));
      final body = _decode(response);
      if (_looksLoggedOut(body)) return '登录已失效，请重新登录';
      if (body.contains('成功') || body.contains('已回复')) return '回复成功';
      final error = RegExp(r'<div class="error">([^<]+)</div>').firstMatch(body)?.group(1);
      if (error != null && error.trim().isNotEmpty) return error.trim();
      return '已提交，回帖结果以帖子页为准';
    } catch (e) {
      return '发送失败：$e';
    }
  }

  /// 收藏 / 顶 / 赞：都是 GET 一个带参数的地址，成功与否看状态码。
  Future<bool> hit(String url) async {
    if (url.isEmpty) return false;
    await YaohuoSession.instance.refresh();
    try {
      final response = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 20));
      return response.statusCode < 400;
    } catch (_) {
      return false;
    }
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
    if (items.isNotEmpty) return items;
    // 兜底：站点改版后 line1/line2 对不上时，直接扫帖子链接（/bbs-123456.html）。
    final seen = <String>{};
    for (final anchor in doc.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      if (!RegExp(r'bbs-\d+\.html').hasMatch(href)) continue;
      final title = anchor.text.trim();
      if (title.isEmpty || !seen.add(href)) continue;
      items.add(YaohuoThreadItem(
        title: title,
        url: _absolute(href),
        author: '',
        reply: '',
        read: '',
        time: '',
      ));
      if (items.length >= 60) break;
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

    final form = doc.querySelector('form[name="f"]');
    String field(String name) =>
        form?.querySelector('input[name="$name"]')?.attributes['value']?.trim() ?? '';

    String actionUrl(String pattern) {
      for (final anchor in doc.querySelectorAll('a[href]')) {
        final href = anchor.attributes['href'] ?? '';
        if (href.contains(pattern)) return _absolute(href);
      }
      return '';
    }

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
      threadId: field('id'),
      classId: field('classid'),
      sid: field('sid'),
      favoriteUrl: actionUrl('action=fav'),
      upUrl: actionUrl('state=1'),
      likeUrl: actionUrl('state=2'),
    );
  }

  static List<YaohuoReply> _parseReplies(dom.Document doc) {
    var rows = doc.querySelectorAll('div.recontent div.reline');
    if (rows.isEmpty) {
      // 站点改版兜底：楼层行都是「[沙发] / [板凳] / [12楼] 开头，带用户名链接和冒号」。
      rows = doc
          .querySelectorAll('div')
          .where((element) => _looksLikeReply(element))
          .toList();
    }
    final replies = <YaohuoReply>[];
    for (final element in rows) {
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
      replies.add(YaohuoReply(floor: floor, author: author, content: _compact(content), time: when));
    }
    return replies;
  }

  static bool _looksLikeReply(dom.Element element) {
    final text = element.text.trim();
    if (text.length < 6 || text.length > 4000) return false;
    final head = RegExp(r'^\[([^\]]{1,6})\]').firstMatch(text);
    if (head == null) return false;
    final label = head.group(1) ?? '';
    final isFloor = label == '沙发' ||
        label == '椅子' ||
        label == '板凳' ||
        label == '地板' ||
        label == '地下室' ||
        RegExp(r'^\d{1,4}楼$').hasMatch(label);
    if (!isFloor) return false;
    if (!text.contains('：')) return false;
    return element.querySelector('a') != null;
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
