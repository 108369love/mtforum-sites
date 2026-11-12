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

/// 帖子详情。
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
    this.replyAction = '',
    this.replyCsrf = '',
    this.favAction = '',
    this.favCsrf = '',
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

  /// 回帖表单：站点的表单带 __CSRFToken，POST 必须带上它和隐藏字段。
  final String threadId;
  final String classId;
  final String replyAction;
  final String replyCsrf;

  /// 收藏表单。
  final String favAction;
  final String favCsrf;
}

/// 妖火网的原生数据层。
///
/// 结构以站点 2026-11 的真实页面为准（对照抓取到的 HTML）：
/// - 列表：`div.listdata`（class 里带 line1/line2），标题是 `a[href*="bbs-"]`，
///   作者在 `span.louzhunicheng`，`N回/M阅` 在行文本里，时间在 `span.right`；
/// - 帖子：`#book-view-content` 里 `.Postinfo` 是 `[标题]…(阅N)` 和 `[时间]`，
///   正文在 `.bbscontent`；楼主在 `.louzhuxinxi .louzhunicheng`；
/// - 回复：`div.recontent div.forum-post`，作者 `.user-nick a`，时间 `.post-date`，
///   楼层 `.floor-number`，内容 `.post-content`；
/// - 回帖表单：`form[name=f]`，`textarea[name=content]` + `__CSRFToken`；
/// - 收藏：`form.fav-form` POST 到 `/bbs/Share.aspx`；
/// - 我的地盘：`div.content` 的「我的ID:1265」；空间：`<b>ID号:</b>1265`。
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
    (id: 204, name: '活动线报'),
    (id: 177, name: '妖火茶馆'),
    (id: 213, name: '悬赏问答'),
    (id: 240, name: '贴图视频'),
    (id: 199, name: '站务处理'),
    (id: 198, name: '投诉建议'),
  ];

  Map<String, String> get _headers => <String, String>{
        'User-Agent': AppConfig.userAgent,
        'Referer': _base,
        'Accept': 'text/html,application/xhtml+xml',
        if (YaohuoSession.instance.cookieHeader.isNotEmpty) 'Cookie': YaohuoSession.instance.cookieHeader,
      };

  Future<String> _fetch(String url, {Map<String, String>? query, String? referer}) async {
    await YaohuoSession.instance.refresh();
    var uri = Uri.parse(url.startsWith('http') ? url : _base + url.replaceFirst(RegExp(r'^/+'), ''));
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: <String, String>{...uri.queryParameters, ...query});
    }
    final headers = <String, String>{..._headers};
    if (referer != null && referer.isNotEmpty) headers['Referer'] = referer;
    final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
    final body = _decode(response);
    if (response.statusCode >= 400) {
      throw StateError('HTTP ${response.statusCode}');
    }
    if (_looksLoggedOut(body)) {
      throw const YaohuoNotLoggedIn();
    }
    return body;
  }

  Future<String> _post(String url, Map<String, String> fields, {String? referer}) async {
    await YaohuoSession.instance.refresh();
    final headers = <String, String>{
      ..._headers,
      'Content-Type': 'application/x-www-form-urlencoded',
      if (referer != null && referer.isNotEmpty) 'Referer': referer,
    };
    final response = await http
        .post(
          Uri.parse(url.startsWith('http') ? url : _base + url.replaceFirst(RegExp(r'^/+'), '')),
          headers: headers,
          body: fields,
        )
        .timeout(const Duration(seconds: 30));
    return _decode(response);
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

  /// 全站热门：站点按时间窗（1/3/7/30 天）给出排行榜。
  Future<List<YaohuoThreadItem>> fetchHotThreads({int days = 1, int page = 1}) async {
    final html = await _fetch('bbs/book_list_hot.aspx', query: <String, String>{
      'classid': '0',
      'days': '$days',
      'page': '$page',
    });
    return parseThreadList(html);
  }

  /// 直接抓一个地址、按帖子列表解析（「我的帖子」这类站点自己给的入口用）。
  Future<List<YaohuoThreadItem>> fetchThreadListFromUrl(String url, {int page = 1}) async {
    final html = await _fetch(_withPage(url, page));
    return parseThreadList(html);
  }

  /// 抓一个地址、按「链接列表」解析（站内信、关注这类列表页）。
  Future<List<({String title, String url, String extra})>> fetchLinkList(String url) async {
    final html = await _fetch(url);
    return parseLinkList(html);
  }

  /// 抓用户资料页，解析成「字段 → 值」。
  Future<Map<String, String>> fetchUserInfo(String url) async {
    final html = await _fetch(url);
    return parseUserInfo(html);
  }

  /// 抓一个没有固定结构的详情页：取最大的一块正文 + 图片。
  Future<({String title, String body, List<String> images})> fetchGenericPage(String url) async {
    final html = await _fetch(url);
    final doc = html_parser.parse(html);
    final titleTag = doc.querySelector('title')?.text.trim() ?? '';
    dom.Element? best;
    var bestLength = 0;
    for (final candidate in doc.querySelectorAll('div.content, div.viewContent, div.listmms')) {
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
    final fragment = html_parser.parseFragment(
      htmlBody.replaceAll(RegExp(r'<script.*?</script>', caseSensitive: false, dotAll: true), ''),
    );
    final images = <String>[];
    for (final img in fragment.querySelectorAll('img')) {
      final src = img.attributes['src'] ?? '';
      if (src.isEmpty || images.contains(src)) continue;
      images.add(_absolute(src));
    }
    return (title: titleTag, body: _compact(fragment.text ?? ''), images: images);
  }

  /// 「我的地盘 / 空间 / 帖子 / 信箱」这几个入口的真实地址。
  Future<List<({String label, String url})>> fetchMyNav() async {
    const labels = <String>['我的地盘', '空间', '帖子', '信箱'];
    const fallback = <String, String>{
      '我的地盘': 'myfile.aspx',
      '空间': 'bbs/userinfo.aspx',
      '帖子': 'bbs/book_list_search.aspx?type=pub&classid=0',
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

  /// 发帖表单：站点把隐藏字段（__CSRFToken/action/classid/siteid）都放在表单里，
  /// 先抓原表单再把标题正文填进去，比手写字段稳。
  Future<({String action, Map<String, String> fields})> fetchComposeForm(int classId) async {
    final html = await _fetch('bbs/book_view_add.aspx', query: <String, String>{'classid': '$classId'});
    final doc = html_parser.parse(html);
    dom.Element? form;
    for (final candidate in doc.querySelectorAll('form')) {
      if (candidate.querySelector('input[name="book_title"]') != null) {
        form = candidate;
        break;
      }
    }
    if (form == null) throw StateError('没找到发帖表单');
    final fields = <String, String>{};
    for (final input in form.querySelectorAll('input[name]')) {
      final name = input.attributes['name'] ?? '';
      if (name.isEmpty) continue;
      fields[name] = input.attributes['value'] ?? '';
    }
    for (final area in form.querySelectorAll('textarea[name]')) {
      final name = area.attributes['name'] ?? '';
      if (name.isEmpty) continue;
      fields[name] = area.text;
    }
    for (final select in form.querySelectorAll('select[name]')) {
      final name = select.attributes['name'] ?? '';
      if (name.isEmpty) continue;
      final selected = select.querySelector('option[selected]');
      fields[name] = selected?.attributes['value'] ?? '';
    }
    return (action: _absolute(form.attributes['action'] ?? 'bbs/book_view_add.aspx'), fields: fields);
  }

  /// 发帖。返回站点的提示文本。
  Future<String> publish({
    required int classId,
    required String title,
    required String content,
    String sendmoney = '',
  }) async {
    try {
      final form = await fetchComposeForm(classId);
      final fields = Map<String, String>.of(form.fields)
        ..['book_title'] = title
        ..['book_content'] = content
        ..['classid'] = '$classId'
        ..['g'] = '';
      if (sendmoney.isNotEmpty) fields['sendmoney'] = sendmoney;
      final body = await _post(
        form.action,
        fields,
        referer: _absolute('bbs/book_view_add.aspx?classid=$classId'),
      );
      if (_looksLoggedOut(body)) return '登录已失效，请重新登录';
      if (body.contains('成功') || body.contains('发表成功')) return '发布成功';
      final tip = RegExp(r'温馨提示[^<]*<br[^>]*>([^<]{2,80})').firstMatch(body)?.group(1);
      if (tip != null && tip.trim().isNotEmpty) return tip.trim();
      final error = RegExp(r'<div class="error">([^<]+)</div>').firstMatch(body)?.group(1);
      if (error != null && error.trim().isNotEmpty) return error.trim();
      return '已提交，发布结果请回列表刷新确认';
    } catch (e) {
      return '发布失败：$e';
    }
  }

  /// 从站点页面里捞板块（论坛首页/站内导航里的 classid 链接）。
  Future<List<({int id, String name})>> fetchBoardsFromSite() async {
    final found = <int, String>{};
    for (final url in <String>['wapindex.aspx?classid=206', 'wapindex.aspx?siteid=1000']) {
      try {
        final html = await _fetch(url);
        final doc = html_parser.parse(html);
        for (final anchor in doc.querySelectorAll('a[href]')) {
          final href = anchor.attributes['href'] ?? '';
          final match = RegExp(r'classid=(\d+)').firstMatch(href);
          if (match == null) continue;
          final id = int.tryParse(match.group(1) ?? '');
          final name = anchor.text.trim();
          if (id == null || id <= 0 || name.isEmpty || name.length > 8) continue;
          found.putIfAbsent(id, () => name);
        }
      } catch (_) {
        // 一个页面拿不到就试下一个。
      }
    }
    final builtin = boards.map((b) => b.id).toSet();
    return found.entries
        .where((entry) => !builtin.contains(entry.key) && ![0, 171, 206, 207, 299].contains(entry.key))
        .map((entry) => (id: entry.key, name: entry.value))
        .toList()
      ..sort((a, b) => a.id - b.id);
  }

  Future<YaohuoThread> fetchThread(String url) async {
    final html = await _fetch(url);
    return parseThread(html, url);
  }

  /// 追加更多回复：返回这一页的回复和「下一页」地址。
  Future<({List<YaohuoReply> replies, String moreUrl})> fetchReplyPage(String url) async {
    final html = await _fetch(url);
    final doc = html_parser.parse(html);
    return (replies: _parseReplies(doc), moreUrl: _moreRepliesUrl(doc));
  }

  /// 回帖：照站点表单 POST，成功与否看返回页的提示。
  Future<String> reply({
    required YaohuoThread thread,
    required String content,
    required String referer,
    String face = '',
    bool notify = true,
  }) async {
    if (thread.replyAction.isEmpty) return '没找到回帖表单，可能需要在浏览器里回复';
    try {
      final body = await _post(
        thread.replyAction,
        <String, String>{
          '__CSRFToken': thread.replyCsrf,
          'content': content,
          'action': 'add',
          'face': face,
          'sendmsg': notify ? '1' : '0',
          'sendmsg2': notify ? '1' : '0',
          'id': thread.threadId,
          'classid': thread.classId,
          'siteid': '1000',
          'lpage': '1',
        },
        referer: referer,
      );
      if (_looksLoggedOut(body)) return '登录已失效，请重新登录';
      if (body.contains('成功') || body.contains(content)) return '回复成功';
      final tip = RegExp(r'温馨提示[^<]*<br[^>]*>([^<]{2,80})').firstMatch(body)?.group(1);
      if (tip != null && tip.trim().isNotEmpty) return tip.trim();
      final error = RegExp(r'<div class="error">([^<]+)</div>').firstMatch(body)?.group(1);
      if (error != null && error.trim().isNotEmpty) return error.trim();
      return '已提交，回帖结果以帖子页为准';
    } catch (e) {
      return '发送失败：$e';
    }
  }

  /// 收藏：站点是 POST 表单，不是 GET 链接。
  Future<bool> favorite(YaohuoThread thread, {required String referer}) async {
    if (thread.favAction.isEmpty) return false;
    try {
      final body = await _post(
        thread.favAction,
        <String, String>{
          '__CSRFToken': thread.favCsrf,
          'action': 'fav',
          'siteid': '1000',
          'classid': thread.classId,
          'id': thread.threadId,
        },
        referer: referer,
      );
      return !_looksLoggedOut(body);
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------- 解析

  static List<YaohuoThreadItem> parseThreadList(String html) {
    final doc = html_parser.parse(html);
    final items = <YaohuoThreadItem>[];
    for (final element in doc.querySelectorAll('div.listdata, div.line1, div.line2')) {
      String? href;
      var title = '';
      for (final anchor in element.querySelectorAll('a[href]')) {
        final candidate = anchor.attributes['href'] ?? '';
        if (!RegExp(r'bbs-\d+\.html').hasMatch(candidate)) continue;
        href = candidate;
        title = anchor.text.trim();
        break;
      }
      if (href == null || title.isEmpty) continue;
      final author = element.querySelector('span.louzhunicheng')?.text.trim() ?? '';
      final time = element.querySelector('span.right')?.text.trim() ?? '';
      final counts = RegExp(r'(\d+)\s*回\s*/\s*(\d+)\s*阅').firstMatch(element.text);
      items.add(YaohuoThreadItem(
        title: title,
        url: _absolute(href),
        author: author,
        reply: counts?.group(1) ?? '',
        read: counts?.group(2) ?? '',
        time: time,
      ));
    }
    if (items.isNotEmpty) return items;
    // 兜底：扫页面里所有帖子链接。
    final seen = <String>{};
    for (final anchor in doc.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      if (!RegExp(r'bbs-\d+\.html').hasMatch(href)) continue;
      final title = anchor.text.trim();
      if (title.isEmpty || !seen.add(href)) continue;
      items.add(YaohuoThreadItem(title: title, url: _absolute(href), author: '', reply: '', read: '', time: ''));
      if (items.length >= 60) break;
    }
    return items;
  }

  static YaohuoThread parseThread(String html, String url) {
    final doc = html_parser.parse(html);
    final root = doc.querySelector('#book-view-content') ?? doc.querySelector('div.content');
    final info = root?.querySelector('.Postinfo');
    final infoText = info?.text ?? '';

    var title = RegExp(r'\[标题\]\s*(.+?)\s*\(阅\d+\)').firstMatch(infoText)?.group(1)?.trim() ?? '';
    if (title.isEmpty) {
      title = RegExp(r'\[标题\]\s*(.+?)\s*\[时间\]').firstMatch(infoText)?.group(1)?.trim() ?? '';
    }
    if (title.isEmpty) {
      title = (doc.querySelector('title')?.text.trim() ?? '').split(' - ').first.trim();
    }
    final reads = RegExp(r'\(阅(\d+)\)').firstMatch(infoText)?.group(1) ?? '';
    final time = doc.querySelector('.DateAndTime')?.text.trim() ??
        RegExp(r'\[时间\]\s*(\d{4}-\d{2}-\d{2}\s+\d{1,2}:\d{2})').firstMatch(infoText)?.group(1) ??
        '';

    final board = _parseBoard(doc);
    final author = doc.querySelector('.louzhuxinxi .louzhunicheng')?.text.trim() ?? '';

    final bodyHtml = root?.querySelector('.bbscontent')?.innerHtml ?? '';
    final cleaned = bodyHtml
        .replaceAll('<!--listS-->', '')
        .replaceAll('<!--listE-->', '')
        .replaceAll(RegExp(r'<div id="KL_show_next_list">[\s\S]*?</div>'), '');
    final fragment = html_parser.parseFragment(cleaned);
    final bodyText = _compact(fragment.text ?? '');
    final images = <String>[];
    for (final img in fragment.querySelectorAll('img')) {
      final src = img.attributes['src'] ?? '';
      if (src.isEmpty || images.contains(src)) continue;
      images.add(_absolute(src));
    }
    final links = <({String text, String url})>[];
    for (final anchor in fragment.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      final text = anchor.text.trim();
      if (href.isEmpty || text.isEmpty) continue;
      links.add((text: text, url: _absolute(href)));
    }

    final replyForm = doc.querySelector('form[name="f"]');
    String formField(dom.Element? form, String name) =>
        form?.querySelector('input[name="$name"]')?.attributes['value']?.trim() ?? '';
    final favForm = doc.querySelector('form.fav-form');

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
      moreUrl: _moreRepliesUrl(doc),
      threadId: formField(replyForm, 'id'),
      classId: formField(replyForm, 'classid'),
      replyAction: _absolute(replyForm?.attributes['action'] ?? ''),
      replyCsrf: formField(replyForm, '__CSRFToken'),
      favAction: _absolute(favForm?.attributes['action'] ?? ''),
      favCsrf: formField(favForm, '__CSRFToken'),
    );
  }

  static String _moreRepliesUrl(dom.Document doc) {
    for (final anchor in doc.querySelectorAll('div.more a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      if (href.isEmpty || href.startsWith('javascript')) continue;
      return _absolute(href);
    }
    return '';
  }

  static List<YaohuoReply> _parseReplies(dom.Document doc) {
    final replies = <YaohuoReply>[];
    for (final element in doc.querySelectorAll('div.recontent div.forum-post')) {
      final floor = element.querySelector('.floor-number')?.text.trim() ??
          (element.attributes['data-floor'] ?? '').trim();
      final author = element.querySelector('.user-nick a')?.text.trim() ?? '';
      final time = element.querySelector('.post-date')?.text.trim() ?? '';
      final content = _compact(element.querySelector('.post-content')?.text.trim() ?? '');
      if (content.isEmpty && author.isEmpty) continue;
      replies.add(YaohuoReply(floor: floor, author: author, content: content, time: time));
    }
    return replies;
  }

  /// 通用链接列表：优先按 `div.line1, div.line2` 拆，退而求其次扫站内链接。
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
      final extra = time.isNotEmpty ? time : _compact(element.text.replaceFirst(title, ''));
      rows.add((title: title, url: _absolute(href), extra: extra));
    }
    if (rows.isNotEmpty) return rows;
    final seen = <String>{};
    for (final anchor in doc.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      final title = anchor.text.trim();
      if (href.isEmpty || title.isEmpty) continue;
      if (!href.contains('.aspx')) continue;
      if (href.contains('wapindex.aspx')) continue;
      if (!seen.add(href)) continue;
      rows.add((title: title, url: _absolute(href), extra: ''));
      if (rows.length >= 60) break;
    }
    return rows;
  }

  /// 用户资料：空间页是 `<b>ID号:</b>1265`，地盘页是 `div.content` 里的「我的ID:1265」。
  static Map<String, String> parseUserInfo(String html) {
    final doc = html_parser.parse(html);
    final info = <String, String>{};

    // 空间页：<b>标签<span class=recolon>:</span></b>值
    for (final bold in doc.querySelectorAll('b')) {
      final label = bold.text.replaceAll(RegExp(r'[:：]\s*$'), '').trim();
      if (label.isEmpty || label.length > 8) continue;
      final parent = bold.parent;
      if (parent == null) continue;
      final siblings = parent.nodes;
      final index = siblings.indexOf(bold);
      if (index < 0) continue;
      var value = '';
      for (var i = index + 1; i < siblings.length; i++) {
        final node = siblings[i];
        if (node is dom.Text) {
          value += node.text;
          if (value.trim().isNotEmpty) break;
        } else {
          // 跳过 <br> 这类空元素，遇到真正的内容元素就停。
          if (node is dom.Element && node.localName != 'br') break;
        }
      }
      value = value.trim();
      if (value.isEmpty || value.length > 40) continue;
      info.putIfAbsent(label, () => value);
    }

    // 地盘页：div.content 里的「键:值」
    for (final content in doc.querySelectorAll('div.content')) {
      final text = _compact(content.text);
      if (text.isEmpty || text.length > 120) continue;
      final match = RegExp(r'^([^:：\n]{1,8})[:：]\s*(\S.*)$').firstMatch(text);
      if (match == null) continue;
      final key = match.group(1)?.trim() ?? '';
      final value = match.group(2)?.trim() ?? '';
      if (key.isEmpty || value.isEmpty) continue;
      info.putIfAbsent(key, () => value);
    }

    // 老格式：【字段】：值
    if (info.isEmpty) {
      final text = doc.querySelector('div.content')?.text ?? doc.body?.text ?? '';
      for (final line in const LineSplitter().convert(text)) {
        final match = RegExp(r'【([^】]{1,12})】\s*[:：]\s*(.*)').firstMatch(line.trim());
        if (match == null) continue;
        final key = match.group(1)?.trim() ?? '';
        final value = match.group(2)?.trim() ?? '';
        if (key.isNotEmpty && value.isNotEmpty) info[key] = value;
      }
    }

    // 表格两列兜底
    if (info.isEmpty) {
      for (final row in doc.querySelectorAll('tr')) {
        final cells = row.querySelectorAll('td, th');
        if (cells.length < 2) continue;
        final key = cells[0].text.trim();
        final value = cells[1].text.trim();
        if (key.isEmpty || value.isEmpty || key.length > 12) continue;
        info[key] = value;
      }
    }
    return info;
  }

  static String _parseBoard(dom.Document doc) {
    for (final title in doc.querySelectorAll('div.title')) {
      final links = title.querySelectorAll('a[href*="book_list.aspx"]');
      if (links.isEmpty) continue;
      return links.last.text.trim();
    }
    final breadcrumb = doc.querySelector('div.title')?.text ?? '';
    final segments = breadcrumb.split(RegExp(r'[>＞]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2) return segments[segments.length - 2];
    return '';
  }

  static String _compact(String text) => text
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  static String _withPage(String url, int page) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return uri.replace(queryParameters: <String, String>{...uri.queryParameters, 'page': '$page'}).toString();
  }

  static String _absolute(String href) {
    if (href.isEmpty) return '';
    if (href.startsWith('http://') || href.startsWith('https://')) return href;
    return Uri.parse(_base).resolve(href.startsWith('/') ? href.substring(1) : href).toString();
  }
}
