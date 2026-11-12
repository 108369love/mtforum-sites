import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_webview_flutter/flutter_inappwebview.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../../services/download_manager.dart';
import 'download_manager_page.dart';
import '../navigation/app_routes.dart';
import '../widgets/glass_menu.dart';
import '../widgets/glass_dialog.dart';

class InternalBrowserPage extends StatefulWidget {
  const InternalBrowserPage({super.key, required this.url, this.title = '内部浏览器'});
  final String url;
  final String title;

  @override
  State<InternalBrowserPage> createState() => _InternalBrowserPageState();
}

class _InternalBrowserPageState extends State<InternalBrowserPage> {
  InAppWebViewController? _controller;
  String _url = '';
  String _title = '正在加载…';
  int _progress = 0;
  bool _loading = true;
  final Set<String> _activeDownloads = <String>{};

  /// 网页自己还能不能后退一层。
  ///
  /// 系统的返回手势（含预测性返回）在 PopScope 上是同步决策的，而
  /// `canGoBack()` 是异步的，所以这里维护一份镜像：每次页面加载完刷新。
  /// 不这么做的话，手势一滑就把整个浏览器页关掉，站内点进去的三四层链接
  /// 全丢，得重新打开。
  bool _canGoBack = false;

  @override
  void initState() {
    super.initState();
    _url = widget.url;
    _title = widget.title;
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(_url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('打开外部浏览器'),
        content: const Text('将离开 MT论坛，交由系统浏览器打开当前链接。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('打开')),
        ],
      ),
    );
    if (confirmed == true) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _downloadCurrentPage() async {
    final uri = Uri.tryParse(_url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('下载文件'),
        content: Text('下载当前地址的内容？\n${uri.pathSegments.isEmpty ? _title : uri.pathSegments.last}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('开始下载')),
        ],
      ),
    );
    if (ok == true) {
      await _startDownload(_url, suggestedFilename: uri.pathSegments.isEmpty ? null : uri.pathSegments.last);
    }
  }

  /// WebView 页面触发文件下载时会走这里，统一接入应用下载管理器。
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该文件已在下载中')));
      return;
    }
    try {
      final cookies = await CookieManager.instance().getCookies(url: WebUri(rawUrl));
      final webCookieHeader = cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
      final record = await DownloadManager.instance.download(
        rawUrl,
        suggestedFilename: suggestedFilename,
        headers: {
          'User-Agent': (userAgent?.trim().isNotEmpty ?? false) ? userAgent!.trim() : AppConfig.userAgent,
          'Referer': _url,
          if (webCookieHeader.isNotEmpty) 'Cookie': webCookieHeader,
          if (webCookieHeader.isEmpty && HttpSession.instance.cookieHeader.isNotEmpty && uri.host == Uri.parse(AppConfig.base).host)
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

  Future<void> _back() async {
    final controller = _controller;
    if (controller == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    if (!await controller.canGoBack()) {
      if (mounted) Navigator.pop(context);
      return;
    }
    // 有些跳转链（百度网盘短链、带口令的分享页）会在历史里留下同一页的多次
    // 跳转：goBack 之后又被服务端 302 拉回来，界面上就是「点了返回没反应」，
    // 系统返回手势也会被一直吞掉，人被困在浏览器里出不去。
    // 减一层历史后如果还停在同一地址，就直接关掉这一页，把人放回帖子。
    final before = await _currentUrl(controller);
    await controller.goBack();
    var after = before;
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      after = await _currentUrl(controller);
      if (after != before) break;
    }
    if (!mounted) return;
    if (after.isEmpty || after == before) {
      Navigator.pop(context);
      return;
    }
    await _refreshBackState();
  }

  /// 当前地址；取不到就用 [onLoadStart]/[onLoadStop] 记下的 [_url] 兜底。
  Future<String> _currentUrl(InAppWebViewController controller) async {
    try {
      final url = await controller.getUrl();
      final text = url?.toString() ?? '';
      if (text.isNotEmpty) return text;
    } catch (_) {
      // 拿不到就走下面的兜底值，不在这里把页面关掉。
    }
    return _url;
  }

  /// 把 WebView 的后退能力同步到 [_canGoBack]。
  Future<void> _refreshBackState() async {
    final controller = _controller;
    if (controller == null) return;
    final canGoBack = await controller.canGoBack();
    if (!mounted || canGoBack == _canGoBack) return;
    setState(() => _canGoBack = canGoBack);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 能后退网页就先退网页，退到底了才关这个页面。这样系统返回手势、
      // 预测性返回的预览、标题栏左上角那颗箭头，三者走的是同一套判断。
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_back());
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back_rounded)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
          Text(_url, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
        ]),
        actions: [
          IconButton(tooltip: '下载当前页面', onPressed: _downloadCurrentPage, icon: const Icon(Icons.download_rounded)),
          IconButton(tooltip: '下载管理', onPressed: () => Navigator.push(context, appRoute(builder: (_) => const DownloadManagerPage())), icon: const Icon(Icons.download_for_offline_outlined)),
          IconButton(tooltip: '外部浏览器打开', onPressed: _openExternal, icon: const Icon(Icons.open_in_browser_rounded)),
          GlassMenuButton<String>(
            tooltip: '更多',
            icon: Icons.more_vert_rounded,
            iconSize: 22,
            hitSize: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            items: const [
              GlassMenuItem(value: 'refresh', label: '刷新', icon: Icons.refresh_rounded),
              GlassMenuItem(value: 'copy', label: '复制链接', icon: Icons.link_rounded),
              // 兜底出口：跳转链把返回吞掉时，至少还有这里能直接回帖子。
              GlassMenuItem(value: 'close', label: '关闭浏览器', icon: Icons.close_rounded),
            ],
            onSelected: (value) async {
              final messenger = ScaffoldMessenger.of(context);
              if (value == 'refresh') await _controller?.reload();
              if (value == 'close' && mounted) {
                Navigator.pop(context);
                return;
              }
              if (value == 'copy') {
                await Clipboard.setData(ClipboardData(text: _url));
                messenger.showSnackBar(const SnackBar(content: Text('链接已复制')));
              }
            },
          ),
        ],
      ),
      body: Column(children: [
        if (_loading) LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100, minHeight: 2),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(widget.url),
              headers: {
                'User-Agent': AppConfig.userAgent,
                if (HttpSession.instance.cookieHeader.isNotEmpty)
                  'Cookie': HttpSession.instance.cookieHeader,
              },
            ),
            initialSettings: InAppWebViewSettings(
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
              if (mounted) {
                setState(() {
                  _progress = progress;
                  _loading = progress < 100;
                });
              }
            },
            onLoadStart: (controller, url) {
              if (mounted) {
                setState(() {
                  _url = url?.toString() ?? _url;
                  _loading = true;
                  _progress = 0;
                });
              }
            },
            onLoadStop: (controller, url) async {
              final title = await controller.getTitle();
              if (mounted) {
                setState(() {
                  _url = url?.toString() ?? _url;
                  _title = (title?.trim().isNotEmpty ?? false) ? title!.trim() : widget.title;
                  _loading = false;
                  _progress = 100;
                });
              }
              // 加载完成后才知道这页之后还能不能退，同步给 PopScope。
              await _refreshBackState();
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
              final uri = Uri.tryParse(action.request.url?.toString() ?? '');
              if (uri == null) return NavigationActionPolicy.CANCEL;
              if (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'about' || uri.scheme == 'data') {
                return NavigationActionPolicy.ALLOW;
              }
              return NavigationActionPolicy.CANCEL;
            },
          ),
        ),
      ]),
    );
  }
}
