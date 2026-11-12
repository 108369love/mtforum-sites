import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_webview_flutter/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../../core/sites.dart';
import '../../services/download_manager.dart';
import '../navigation/app_routes.dart';
import '../widgets/glass_dialog.dart';
import '../widgets/glass_menu.dart';
import 'site_picker_page.dart';
import 'download_manager_page.dart';

/// 地址栏右上角切换的搜索引擎。
class _SearchEngine {
  const _SearchEngine(this.name, this.template);

  final String name;

  /// `%s` 会被替换成经过 encode 的查询词。
  final String template;
}

/// 内置浏览器里的一条历史 / 收藏记录。
class WebEntry {
  const WebEntry({required this.title, required this.url, required this.time});

  final String title;
  final String url;
  final int time;

  Map<String, Object> toJson() => {'t': title, 'u': url, 'ts': time};

  static WebEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['u'];
    if (url is! String || url.isEmpty) return null;
    final title = raw['t'];
    final ts = raw['ts'];
    return WebEntry(
      title: title is String && title.isNotEmpty ? title : url,
      url: url,
      time: ts is int ? ts : 0,
    );
  }
}

/// 内置浏览器。
///
/// 参照 Android 原生 WebView 浏览器常见的那套做：可编辑地址栏、前进/后退、
/// 主页（快捷入口 + 收藏 + 最近访问）、页内查找、桌面版 UA、深色阅读；
/// 新窗口与 `target=_blank` 统一收成当前窗口，弹窗直接拦掉。
///
/// 和原生浏览器最大的不同是没有标签页：Flutter 里每个 WebView 都是一块独立
/// 平台视图，多标签同时存活的内存代价比原生高得多；站内「点开链接看一眼」
/// 的场景，单窗口 + 后退到底再关页已经够用。
class InternalBrowserPage extends StatefulWidget {
  const InternalBrowserPage({super.key, required this.url, this.title = '内部浏览器', this.site});

  final String url;
  final String title;

  /// 非空表示这一页是「站点模式」的根页面（XDA / 妖火 / 自定义站点）：
  /// 底部挂站点快捷入口，菜单里给「切换站点」，返回到底直接退应用而不是弹路由。
  final SiteProfile? site;

  @override
  State<InternalBrowserPage> createState() => _InternalBrowserPageState();
}

class _InternalBrowserPageState extends State<InternalBrowserPage> {
  static const String _historyKey = 'mt_forum_web_history';
  static const String _bookmarkKey = 'mt_forum_web_bookmarks';
  static const int _historyLimit = 100;

  static const String _engineKey = 'mt_forum_web_engine';
  static const String _incognitoKey = 'mt_forum_web_incognito';
  static const String _adBlockKey = 'mt_forum_web_adblock';

  static const List<_SearchEngine> _engines = <_SearchEngine>[
    _SearchEngine('百度', 'https://www.baidu.com/s?wd=%s'),
    _SearchEngine('必应', 'https://cn.bing.com/search?q=%s'),
    _SearchEngine('谷歌', 'https://www.google.com/search?q=%s'),
    _SearchEngine('搜狗', 'https://www.sogou.com/web?query=%s'),
    _SearchEngine('360搜索', 'https://www.so.com/s?q=%s'),
    _SearchEngine('神马', 'https://m.sm.cn/s?q=%s'),
    _SearchEngine('头条搜索', 'https://so.toutiao.com/search?keyword=%s'),
    _SearchEngine('夸克', 'https://quark.sm.cn/s?q=%s'),
    _SearchEngine('DuckDuckGo', 'https://duckduckgo.com/?q=%s'),
  ];

  /// 广告 / 统计域名。只收灰度最低的一批：拦错了顶多少个统计像素，
  /// 不会把站点功能打死（EasyList 那种整库规则留给以后做）。
  static const List<String> _adHosts = <String>[
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'adservice.google.com',
    'umeng.com',
    'cnzz.com',
    'hm.baidu.com',
    'pos.baidu.com',
    'cpro.baidu.com',
    'tanx.com',
    'alimama.com',
    'mmstat.com',
    'gdt.qq.com',
    'adnxs.com',
    'scorecardresearch.com',
  ];

  static const String _desktopUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  InAppWebViewController? _controller;
  final TextEditingController _address = TextEditingController();
  final FocusNode _addressFocus = FocusNode();
  final TextEditingController _findField = TextEditingController();

  String _url = '';
  String _pageTitle = '';
  int _progress = 0;
  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _desktop = false;
  bool _dark = false;
  bool _home = false;
  bool _findOpen = false;
  int _engineIndex = 0;
  bool _incognito = false;
  bool _adBlock = true;
  int _blocked = 0;

  List<WebEntry> _history = <WebEntry>[];
  List<WebEntry> _bookmarks = <WebEntry>[];

  final Set<String> _activeDownloads = <String>{};

  String get _effectiveUrl => _url.isEmpty ? widget.url : _url;

  String get _userAgent => _desktop ? _desktopUA : AppConfig.userAgent;

  /// 只给 MT论坛 自己带登录 Cookie。
  ///
  /// 早先是不管去哪都带上论坛 Cookie——点开一个第三方链接就把登录态一起送出去，
  /// 没必要冒这个险。
  bool get _isMtHost => Uri.tryParse(_effectiveUrl)?.host == AppConfig.host;

  bool get _isBookmarked => _bookmarks.any((entry) => entry.url == _url);

  @override
  void initState() {
    super.initState();
    _url = widget.url;
    _pageTitle = widget.title;
    _address.text = _url;
    unawaited(_loadStored());
  }

  @override
  void dispose() {
    _address.dispose();
    _addressFocus.dispose();
    _findField.dispose();
    super.dispose();
  }

  Future<void> _loadStored() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = _decode(prefs.getString(_historyKey));
      final bookmarks = _decode(prefs.getString(_bookmarkKey));
      final engine = prefs.getInt(_engineKey) ?? 0;
      final incognito = prefs.getBool(_incognitoKey) ?? false;
      final adBlock = prefs.getBool(_adBlockKey) ?? true;
      if (!mounted) return;
      setState(() {
        _history = history;
        _bookmarks = bookmarks;
        _engineIndex = engine < 0 || engine >= _engines.length ? 0 : engine;
        _incognito = incognito;
        _adBlock = adBlock;
      });
    } catch (_) {
      // 本地记录读不出来只是没有历史和收藏，不影响浏览。
    }
  }

  List<WebEntry> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <WebEntry>[];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return <WebEntry>[];
      return data.map(WebEntry.fromJson).whereType<WebEntry>().toList();
    } catch (_) {
      return <WebEntry>[];
    }
  }

  Future<void> _persist(String key, List<WebEntry> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(items.map((e) => e.toJson()).toList()));
    } catch (_) {
      // 存不下就只在本次会话里记着。
    }
  }

  Future<void> _saveSetting(String key, Object value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is int) await prefs.setInt(key, value);
      if (value is bool) await prefs.setBool(key, value);
    } catch (_) {
      // 存不下就只在本次会话里生效。
    }
  }

  String _searchUrl(String text) {
    final engine = _engines[_engineIndex];
    return engine.template.replaceFirst('%s', Uri.encodeQueryComponent(text));
  }

  bool _isAdUrl(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return false;
    for (final ad in _adHosts) {
      if (host == ad || host.endsWith('.$ad')) return true;
    }
    return false;
  }

  String _permissionLabel(String name) {
    if (name == 'CAMERA') return '摄像头';
    if (name == 'MICROPHONE' || name == 'AUDIO_CAPTURE') return '麦克风';
    if (name == 'CAMERA_AND_MICROPHONE') return '摄像头与麦克风';
    if (name == 'GEOLOCATION') return '定位';
    if (name == 'PROTECTED_MEDIA_ID') return '受保护媒体';
    return name.toLowerCase();
  }

  Future<bool> _confirmPermission(String resources) async {
    if (!mounted) return false;
    final allowed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('网站请求权限'),
        content: Text('$resources\n\n只有你点「允许」时，这次请求才会放行。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('拒绝')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('允许')),
        ],
      ),
    );
    return allowed == true;
  }

  /// 唤起外部应用前先问一句，避免点个链接就被拉去装东西。
  Future<bool> _confirmExternalApp(String url) async {
    if (!mounted) return false;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('跳转到外部应用'),
        content: Text('这个链接要唤起手机上的其它应用：\n$url'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('打开')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _recordVisit(String url, String title) async {
    if (url.isEmpty || url.startsWith('about:') || url.startsWith('data:')) return;
    final entry = WebEntry(
      title: title.trim().isEmpty ? url : title.trim(),
      url: url,
      time: DateTime.now().millisecondsSinceEpoch,
    );
    final next = <WebEntry>[entry, ..._history.where((e) => e.url != url)];
    if (next.length > _historyLimit) next.removeRange(_historyLimit, next.length);
    if (mounted) setState(() => _history = next);
    await _persist(_historyKey, next);
  }

  Future<void> _toggleBookmark() async {
    final url = _url;
    if (url.isEmpty) return;
    final next = List<WebEntry>.of(_bookmarks);
    final index = next.indexWhere((entry) => entry.url == url);
    final added = index < 0;
    if (added) {
      next.insert(
        0,
        WebEntry(
          title: _pageTitle.trim().isEmpty ? url : _pageTitle.trim(),
          url: url,
          time: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } else {
      next.removeAt(index);
    }
    setState(() => _bookmarks = next);
    await _persist(_bookmarkKey, next);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(added ? '已收藏' : '已取消收藏')));
  }

  /// 地址栏输入：完整地址直接开，像域名就补 https，其余当搜索词。
  String _normalize(String input) {
    final text = input.trim();
    if (text.isEmpty) return '';
    final lower = text.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('about:') ||
        lower.startsWith('file:')) {
      return text;
    }
    final looksLikeHost = !text.contains(' ') && (text.contains('.') || text.startsWith('localhost'));
    if (looksLikeHost) return 'https://$text';
    return _searchUrl(text);
  }

  Future<void> _go(String input) async {
    final target = _normalize(input);
    if (target.isEmpty) return;
    final controller = _controller;
    if (controller == null) {
      if (!mounted) return;
      setState(() {
        _url = target;
        _home = false;
      });
      _address.text = target;
      return;
    }
    setState(() => _home = false);
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(target), headers: {'User-Agent': _userAgent}));
  }

  Future<void> _openEntry(WebEntry entry) async {
    _address.text = entry.url;
    await _go(entry.url);
  }

  /// 退到没有网页历史时的出口：普通页面弹路由，站点模式（根页面）退应用。
  void _leavePage() {
    if (widget.site != null) {
      unawaited(SystemNavigator.pop());
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _back() async {
    final controller = _controller;
    if (controller == null) {
      _leavePage();
      return;
    }
    if (!await controller.canGoBack()) {
      _leavePage();
      return;
    }
    // 有些跳转链（百度网盘短链、带口令的分享页）会在历史里留下同一页的多次
    // 跳转：goBack 之后又被服务端 302 拉回来，界面上就是「点了返回没反应」，
    // 系统返回手势也会被一直吞掉，人被困在浏览器里出不去。
    // 等这一跳落定后地址还没变，就直接关掉这一页，把人放回帖子。
    final before = await _currentUrl(controller);
    await controller.goBack();
    for (var i = 0; i < 10 && _loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    final after = await _currentUrl(controller);
    if (after.isEmpty || after == before) {
      _leavePage();
      return;
    }
    await _refreshNavState();
  }

  Future<void> _hierarchyBack() async {
    if (_home) {
      setState(() => _home = false);
      return;
    }
    await _back();
  }

  Future<void> _forward() async {
    final controller = _controller;
    if (controller == null) return;
    if (!await controller.canGoForward()) return;
    await controller.goForward();
    await _refreshNavState();
  }

  Future<String> _currentUrl(InAppWebViewController controller) async {
    try {
      final url = await controller.getUrl();
      final text = url?.toString() ?? '';
      if (text.isNotEmpty) return text;
    } catch (_) {
      // 拿不到就用记着的地址兜底，不在这里把页面关掉。
    }
    return _url;
  }

  Future<void> _refreshNavState() async {
    final controller = _controller;
    if (controller == null) return;
    final canGoBack = await controller.canGoBack();
    final canGoForward = await controller.canGoForward();
    if (!mounted) return;
    if (canGoBack == _canGoBack && canGoForward == _canGoForward) return;
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  /// 注入增强脚本：新窗口收成当前窗口、拦掉 window.open 弹窗、按需套深色滤镜。
  ///
  /// 站点改版顶多让这些修补失效，不能影响页面本身，所以整段吞异常。
  Future<void> _injectEnhancements(InAppWebViewController controller) async {
    final dark = _dark
        ? '''
  (function () {
    if (document.getElementById('mtforum-force-dark')) return;
    var style = document.createElement('style');
    style.id = 'mtforum-force-dark';
    style.textContent = 'html{filter:invert(1) hue-rotate(180deg);background:#0f0f0f!important}'
      + 'img,video,picture,canvas,svg,iframe{filter:invert(1) hue-rotate(180deg)}';
    (document.head || document.documentElement).appendChild(style);
  })();
'''
        : '''
  (function () {
    var style = document.getElementById('mtforum-force-dark');
    if (style) style.remove();
  })();
''';
    final script = '''
(function () {
  try {
    var links = document.querySelectorAll('a[target="_blank"]');
    for (var i = 0; i < links.length; i++) { links[i].removeAttribute('target'); }
    if (!window.__mtForumNoPopup) {
      window.__mtForumNoPopup = true;
      window.open = function () { return null; };
    }
  } catch (e) {}
})();
$dark''';
    try {
      await controller.evaluateJavascript(source: script);
    } catch (_) {
      // 忽略：没套上增强也只是页面朴素一点。
    }
  }

  Future<void> _switchSite() async {
    await Navigator.of(context).push(appRoute(builder: (_) => const SitePickerPage()));
  }

  Future<void> _pickEngine() async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text('搜索引擎', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (var i = 0; i < _engines.length; i++)
              ListTile(
                title: Text(_engines[i].name),
                trailing: i == _engineIndex ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(sheetContext, i),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    setState(() => _engineIndex = chosen);
    await _saveSetting(_engineKey, chosen);
  }

  Future<void> _toggleIncognito() async {
    final next = !_incognito;
    setState(() => _incognito = next);
    await _saveSetting(_incognitoKey, next);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(next ? '无痕模式：这次浏览不写历史' : '已退出无痕模式')));
  }

  Future<void> _toggleAdBlock() async {
    final next = !_adBlock;
    setState(() {
      _adBlock = next;
      if (next) _blocked = 0;
    });
    await _saveSetting(_adBlockKey, next);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(next ? '广告拦截已开启' : '广告拦截已关闭')));
  }

  Future<void> _toggleDesktop() async {
    setState(() {
      _desktop = !_desktop;
      _address.text = _effectiveUrl;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_desktop ? '已切换桌面版，正在重载' : '已切回手机版，正在重载')));
  }

  Future<void> _toggleDark() async {
    setState(() => _dark = !_dark);
    final controller = _controller;
    if (controller != null) await _injectEnhancements(controller);
  }

  Future<void> _toggleFind() async {
    final open = !_findOpen;
    setState(() => _findOpen = open);
    if (!open) {
      await _controller?.clearMatches();
      _findField.clear();
    }
  }

  Future<void> _findNext(bool forward) async {
    final controller = _controller;
    final text = _findField.text.trim();
    if (controller == null || text.isEmpty) return;
    await controller.findAllAsync(find: text);
    if (!forward) await controller.findNext(forward: false);
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(_url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyLink() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _url));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('链接已复制')));
  }

  Future<void> _clearData() async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('清除浏览数据'),
        content: const Text('将清空内置浏览器的 Cookie、缓存和历史记录，已登录的站点会退出。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清除')),
        ],
      ),
    );
    if (confirmed != true) return;
    await CookieManager.instance().deleteAllCookies();
    await _controller?.clearCache();
    setState(() => _history = <WebEntry>[]);
    await _persist(_historyKey, <WebEntry>[]);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已清除浏览数据')));
  }

  /// WebView 页面触发文件下载时走这里，统一接入应用下载管理器。
  Future<void> _startDownload(
    String rawUrl, {
    String? suggestedFilename,
    String? userAgent,
    String? contentDisposition,
  }) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('不支持此下载链接')));
      }
      return;
    }
    if (!_activeDownloads.add(rawUrl)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该文件已在下载中')));
      }
      return;
    }
    try {
      final cookies = await CookieManager.instance().getCookies(url: WebUri(rawUrl));
      final webCookieHeader = cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
      final record = await DownloadManager.instance.download(
        rawUrl,
        suggestedFilename: suggestedFilename,
        headers: {
          'User-Agent': (userAgent?.trim().isNotEmpty ?? false) ? userAgent!.trim() : _userAgent,
          'Referer': _url,
          if (webCookieHeader.isNotEmpty) 'Cookie': webCookieHeader,
          if (webCookieHeader.isEmpty && _isMtHost && HttpSession.instance.cookieHeader.isNotEmpty)
            'Cookie': HttpSession.instance.cookieHeader,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载完成：${record.name}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败：$e')));
      }
    } finally {
      _activeDownloads.remove(rawUrl);
    }
  }

  Future<void> _showHistorySheet() async {
    final scheme = Theme.of(context).colorScheme;
    final items = List<WebEntry>.of(_history);
    final chosen = await showModalBottomSheet<WebEntry>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('历史记录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    TextButton(
                      onPressed: items.isEmpty
                          ? null
                          : () async {
                              setState(() => _history = <WebEntry>[]);
                              await _persist(_historyKey, <WebEntry>[]);
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                            },
                      child: const Text('清空'),
                    ),
                  ],
                ),
              ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
                  child: Text('还没有浏览记录', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
                    itemBuilder: (context, index) {
                      final entry = items[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.history_rounded, size: 20, color: scheme.onSurfaceVariant),
                        title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(entry.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.pop(sheetContext, entry),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) await _openEntry(chosen);
  }

  /// 顶部玻璃菜单。
  Future<void> _openMenu(BuildContext context) async {
    final items = <GlassMenuItem<String>>[
      const GlassMenuItem(value: 'home', label: '主页', icon: Icons.home_outlined),
      GlassMenuItem(
        value: 'bookmark',
        label: _isBookmarked ? '取消收藏' : '收藏此页',
        icon: _isBookmarked ? Icons.star_rounded : Icons.star_outline_rounded,
      ),
      const GlassMenuItem(value: 'history', label: '历史记录', icon: Icons.history_rounded),
      const GlassMenuItem(value: 'find', label: '页内查找', icon: Icons.search_rounded),
      GlassMenuItem(
        value: 'engine',
        label: '搜索引擎 · ${_engines[_engineIndex].name}',
        icon: Icons.manage_search_rounded,
      ),
      GlassMenuItem(
        value: 'incognito',
        label: _incognito ? '退出无痕模式' : '无痕模式（不记历史）',
        icon: Icons.visibility_off_outlined,
      ),
      GlassMenuItem(
        value: 'adblock',
        label: _adBlock ? '广告拦截已开 · 拦了 $_blocked 条' : '开启广告拦截',
        icon: Icons.block_rounded,
      ),
      GlassMenuItem(
        value: 'desktop',
        label: _desktop ? '手机版网站' : '桌面版网站',
        icon: Icons.desktop_windows_outlined,
      ),
      GlassMenuItem(
        value: 'dark',
        label: _dark ? '关闭深色阅读' : '深色阅读',
        icon: Icons.dark_mode_outlined,
      ),
      const GlassMenuItem(value: 'copy', label: '复制链接', icon: Icons.link_rounded),
      const GlassMenuItem(value: 'external', label: '外部浏览器打开', icon: Icons.open_in_browser_rounded),
      const GlassMenuItem(value: 'downloads', label: '下载管理', icon: Icons.download_for_offline_outlined),
      const GlassMenuItem(value: 'clear', label: '清除浏览数据', icon: Icons.delete_outline_rounded, danger: true),
      if (widget.site != null)
        const GlassMenuItem(value: 'switchSite', label: '切换站点', icon: Icons.swap_horiz_rounded)
      else
        const GlassMenuItem(value: 'close', label: '关闭浏览器', icon: Icons.close_rounded),
    ];
    final box = context.findRenderObject() as RenderBox?;
    final anchor = box == null
        ? Rect.fromLTWH(MediaQuery.sizeOf(context).width - 240, 60, 1, 1)
        : Rect.fromPoints(
            box.localToGlobal(Offset(box.size.width - 12, 56)),
            box.localToGlobal(Offset(box.size.width, 56)),
          );
    final value = await showGlassMenu<String>(context, anchor: anchor, items: items, dividers: true);
    if (value == null || !mounted) return;
    if (value == 'home') {
      setState(() => _home = true);
      return;
    }
    if (value == 'bookmark') {
      await _toggleBookmark();
      return;
    }
    if (value == 'history') {
      await _showHistorySheet();
      return;
    }
    if (value == 'find') {
      await _toggleFind();
      return;
    }
    if (value == 'engine') {
      await _pickEngine();
      return;
    }
    if (value == 'incognito') {
      await _toggleIncognito();
      return;
    }
    if (value == 'adblock') {
      await _toggleAdBlock();
      return;
    }
    if (value == 'desktop') {
      await _toggleDesktop();
      return;
    }
    if (value == 'dark') {
      await _toggleDark();
      return;
    }
    if (value == 'copy') {
      await _copyLink();
      return;
    }
    if (value == 'external') {
      await _openExternal();
      return;
    }
    if (value == 'downloads') {
      if (!mounted) return;
      await Navigator.of(context).push(appRoute(builder: (_) => const DownloadManagerPage()));
      return;
    }
    if (value == 'clear') {
      await _clearData();
      return;
    }
    if (value == 'switchSite') {
      await _switchSite();
      return;
    }
    if (value == 'close' && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_home && !_canGoBack,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_hierarchyBack());
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: widget.site == null
              ? IconButton(
                  tooltip: '返回',
                  onPressed: _hierarchyBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : null,
          titleSpacing: 12,
          title: _addressBar(context, scheme),
          actions: [
            if (_incognito)
              const Padding(
                padding: EdgeInsets.only(right: 2),
                child: Tooltip(message: '无痕模式', child: Icon(Icons.visibility_off_rounded, size: 18)),
              ),
            IconButton(
              tooltip: _loading ? '停止' : '刷新',
              onPressed: () {
                if (_loading) {
                  unawaited(_controller?.stopLoading());
                } else {
                  unawaited(_controller?.reload());
                }
              },
              icon: Icon(_loading ? Icons.close_rounded : Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: '前进',
              onPressed: _canGoForward ? _forward : null,
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
            Builder(
              builder: (menuContext) => IconButton(
                tooltip: '更多',
                onPressed: () => unawaited(_openMenu(menuContext)),
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_loading)
              LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100, minHeight: 2),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _webView(context)),
                  if (_home) Positioned.fill(child: _homeView(context, scheme)),
                ],
              ),
            ),
            if (_findOpen) _findBar(context, scheme),
            _siteQuickBar(context, scheme),
          ],
        ),
      ),
    );
  }

  Widget _addressBar(BuildContext context, ColorScheme scheme) {
    return Container(
      height: 38,
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(19),
      ),
      child: Row(
        children: [
          Icon(Icons.language_rounded, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _address,
              focusNode: _addressFocus,
              textInputAction: TextInputAction.go,
              keyboardType: TextInputType.url,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '输入网址或搜索内容',
                hintStyle: TextStyle(fontSize: 13),
              ),
              onTap: () {
                // 点进来就是「要改地址」，整段选中比让用户自己长按省事。
                final text = _address.text;
                _address.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
              },
              onSubmitted: (value) {
                _addressFocus.unfocus();
                unawaited(_go(value));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _webView(BuildContext context) {
    return InAppWebView(
      // 桌面版切换要重建 WebView 才能换 UA：initialSettings 只在创建时生效。
      key: ValueKey<String>('browser-${_desktop ? 'desktop' : 'mobile'}'),
      initialUrlRequest: URLRequest(
        url: WebUri(_effectiveUrl),
        headers: {
          'User-Agent': _userAgent,
          if (_isMtHost && HttpSession.instance.cookieHeader.isNotEmpty)
            'Cookie': HttpSession.instance.cookieHeader,
        },
      ),
      initialSettings: InAppWebViewSettings(
        userAgent: _userAgent,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        useShouldOverrideUrlLoading: true,
        allowsBackForwardNavigationGestures: true,
        thirdPartyCookiesEnabled: true,
        supportMultipleWindows: false,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
      },
      onProgressChanged: (controller, progress) {
        if (!mounted) return;
        setState(() {
          _progress = progress;
          _loading = progress < 100;
        });
      },
      onLoadStart: (controller, url) {
        if (!mounted) return;
        setState(() {
          _url = url?.toString() ?? _url;
          _loading = true;
          _progress = 0;
        });
        if (!_addressFocus.hasFocus) _address.text = _url;
      },
      onLoadStop: (controller, url) async {
        final title = await controller.getTitle();
        final current = url?.toString() ?? _url;
        if (!mounted) return;
        setState(() {
          _url = current;
          if (title != null && title.trim().isNotEmpty) _pageTitle = title.trim();
          _loading = false;
          _progress = 100;
        });
        if (!_addressFocus.hasFocus) _address.text = current;
        await _injectEnhancements(controller);
        await _refreshNavState();
        if (!_incognito) await _recordVisit(current, _pageTitle);
      },
      onPermissionRequest: (controller, request) async {
        final labels = request.resources.map((r) => _permissionLabel(r.name())).join('、');
        final allowed = await _confirmPermission(labels.isEmpty ? '未知权限' : labels);
        return PermissionResponse(
          resources: request.resources,
          action: allowed ? PermissionResponseAction.GRANT : PermissionResponseAction.DENY,
        );
      },
      shouldInterceptRequest: (controller, request) async {
        if (!_adBlock) return null;
        final url = request.url.toString();
        if (!_isAdUrl(url)) return null;
        // 只把命中名单的请求换成空响应，不碰页面其它资源。
        _blocked += 1;
        return WebResourceResponse(
          contentType: 'text/plain',
          contentEncoding: 'utf-8',
          data: Uint8List(0),
          statusCode: 200,
          reasonPhrase: 'OK',
          headers: const <String, String>{'Access-Control-Allow-Origin': '*'},
        );
      },
      onDownloadStarting: (controller, request) async {
        unawaited(_startDownload(
          request.url.toString(),
          suggestedFilename: request.suggestedFilename,
          userAgent: request.userAgent,
          contentDisposition: request.contentDisposition,
        ));
        return null;
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final raw = action.request.url?.toString() ?? '';
        final uri = Uri.tryParse(raw);
        if (uri == null) return NavigationActionPolicy.CANCEL;
        if (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'about' || uri.scheme == 'data') {
          return NavigationActionPolicy.ALLOW;
        }
        // mailto / market / intent 这类交给系统，WebView 自己开不了；
        // 先问一句，别让一个链接把用户直接拽去装东西。
        if (await canLaunchUrl(uri)) {
          final ok = await _confirmExternalApp(raw);
          if (ok) await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        return NavigationActionPolicy.CANCEL;
      },
    );
  }

  Widget _findBar(BuildContext context, ColorScheme scheme) {
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          height: 52,
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)))),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _findField,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '在页面中查找',
                    hintStyle: TextStyle(fontSize: 13),
                  ),
                  onSubmitted: (_) => unawaited(_findNext(true)),
                ),
              ),
              IconButton(
                tooltip: '上一个',
                onPressed: () => unawaited(_findNext(false)),
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
              IconButton(
                tooltip: '下一个',
                onPressed: () => unawaited(_findNext(true)),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
              IconButton(
                tooltip: '关闭查找',
                onPressed: () => unawaited(_toggleFind()),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 站点模式底部快捷入口（首页/论坛/登录…），和站点表里配的一致。
  Widget _siteQuickBar(BuildContext context, ColorScheme scheme) {
    final site = widget.site;
    final links = site?.quickLinks ?? const <SiteQuickLink>[];
    if (site == null || links.isEmpty) return const SizedBox.shrink();
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
          ),
          child: Row(
            children: [
              for (final link in links)
                Expanded(
                  child: InkWell(
                    onTap: () => unawaited(_go(site.uri(link.path).toString())),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(link.icon, size: 20, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 2),
                        Text(link.label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeView(BuildContext context, ColorScheme scheme) {
    final shortcuts = <(String, String, IconData)>[
      ('MT论坛', 'https://bbs.binmt.cc/', Icons.forum_outlined),
      ('XDA', 'https://xdaforums.com/', Icons.public_rounded),
      ('妖火网', 'https://yaohuo.me/', Icons.local_fire_department_outlined),
      ('百度', 'https://www.baidu.com/', Icons.search_rounded),
    ];
    return Material(
      color: scheme.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          Text('快捷入口', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in shortcuts)
                ActionChip(
                  avatar: Icon(item.$3, size: 16, color: scheme.primary),
                  label: Text(item.$1),
                  onPressed: () {
                    _address.text = item.$2;
                    unawaited(_go(item.$2));
                  },
                ),
            ],
          ),
          if (_bookmarks.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('收藏', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            for (final entry in _bookmarks.take(10))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.star_outline_rounded, size: 20, color: scheme.primary),
                title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(entry.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => unawaited(_openEntry(entry)),
              ),
          ],
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('最近访问', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            for (final entry in _history.take(20))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.history_rounded, size: 20, color: scheme.onSurfaceVariant),
                title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(entry.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => unawaited(_openEntry(entry)),
              ),
          ],
        ],
      ),
    );
  }
}
