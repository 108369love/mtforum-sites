import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_webview_flutter/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/sites.dart';
import '../navigation/app_routes.dart';
import '../widgets/glass_dialog.dart';
import 'site_picker_page.dart';

/// 用内置浏览器承载一个站点。
///
/// XDA 这类 XenForo 站点挂在 Bunny Shield 后面：首页、版块、RSS 都先回一个
/// 挑战页，页面里的 JS 用 WASM 跑完 Argon2 才发 Cookie 放行（见 docs/SITES.md）。
/// 纯 Dart 的 http 客户端过不去，也没有稳定的 HTML 结构可以解析，所以这里
/// 不再假装能解析它：站点自己的前端跑在 WebView 里，登录态、发帖、附件下载
/// 全部走站点原流程，应用只补壳层——顶栏、快捷入口、返回手势。
class SiteWebPage extends StatefulWidget {
  const SiteWebPage({super.key});

  @override
  State<SiteWebPage> createState() => _SiteWebPageState();
}

class _SiteWebPageState extends State<SiteWebPage> {
  /// 站点在 initState 里定下来；切换站点由 AppShell 换 key 重建本页。
  late final SiteProfile _site = SiteStore.instance.current;

  InAppWebViewController? _controller;
  String _url = '';
  int _progress = 0;
  bool _loading = true;

  /// 网页自己还能不能后退一层。
  ///
  /// 预测性返回要在手势开始时就决定「退网页还是退应用」，而 `canGoBack()`
  /// 是异步的，所以在每次加载完成时把答案抄一份到本地。
  bool _canGoBack = false;

  @override
  void initState() {
    super.initState();
    _url = _site.homeUrl;
  }

  Future<void> _back() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      await _refreshBackState();
    } else if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _refreshBackState() async {
    final controller = _controller;
    if (controller == null) return;
    final canGoBack = await controller.canGoBack();
    if (!mounted) return;
    setState(() => _canGoBack = canGoBack);
  }

  Future<void> _go(String path) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(_site.uri(path).toString())));
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

  Future<void> _openSitePicker() async {
    await Navigator.of(context).push(appRoute(builder: (_) => const SitePickerPage()));
  }

  /// 清掉 WebView 里的 Cookie 和缓存。
  ///
  /// 站点登录态只存在 WebView 的 Cookie 里，换账号时得有个地方能清干净，
  /// 否则退回「我的」页面还会是上一个账号。
  Future<void> _clearSiteData() async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('清除站点数据'),
        content: Text('将清空 ${_site.name} 在这个浏览器里的 Cookie 与缓存，已登录的账号会退出。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清除')),
        ],
      ),
    );
    if (confirmed != true) return;
    final controller = _controller;
    await CookieManager.instance().deleteAllCookies();
    await controller?.clearCache();
    await controller?.reload();
  }

  /// 站点改版顶多是这些修补失效，不能影响页面本身，所以整段吞异常。
  Future<void> _applySiteTweaks(InAppWebViewController controller) async {
    try {
      await controller.evaluateJavascript(source: _tweakScript);
    } catch (_) {
      // 忽略：没套上样式也只是页面朴素一点。
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_back());
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_site.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(
              _url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => _controller?.reload(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '外部浏览器打开',
            onPressed: _openExternal,
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              // 用 if 而不是 switch：这几个动作都是「发出去就不管」，没有返回值。
              if (value == 'site') unawaited(_openSitePicker());
              if (value == 'copy') unawaited(_copyLink());
              if (value == 'clear') unawaited(_clearSiteData());
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'site', child: Text('切换站点')),
              PopupMenuItem(value: 'copy', child: Text('复制当前链接')),
              PopupMenuItem(value: 'clear', child: Text('清除站点数据')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100, minHeight: 2),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(_site.homeUrl),
                headers: {
                  // 用移动端 UA：XenForo 的响应式模板按 UA 决定导航形态。
                  'User-Agent': AppConfig.userAgent,
                },
              ),
              initialSettings: InAppWebViewSettings(
                // UA 必须在设置里给：URLRequest 的 User-Agent 头对首屏请求不一定生效，
                // 站点按 UA 决定给移动端还是桌面模板，这里错了排版会整个不对。
                userAgent: AppConfig.userAgent,
                javaScriptEnabled: true,
                domStorageEnabled: true,
                useShouldOverrideUrlLoading: true,
                allowsBackForwardNavigationGestures: true,
                // 站点的挑战页要读第三方域（bunny.net、CDN）的存储，关掉会卡在挑战上。
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
              },
              onLoadStop: (controller, url) async {
                if (mounted) {
                  setState(() {
                    _url = url?.toString() ?? _url;
                    _loading = false;
                    _progress = 100;
                  });
                }
                await _applySiteTweaks(controller);
                await _refreshBackState();
              },
              shouldOverrideUrlLoading: (controller, action) async {
                final raw = action.request.url?.toString() ?? '';
                final uri = Uri.tryParse(raw);
                if (uri == null) return NavigationActionPolicy.CANCEL;
                if (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'about' || uri.scheme == 'data') {
                  return NavigationActionPolicy.ALLOW;
                }
                // mailto / market / intent 这类交给系统，WebView 自己开不了。
                if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                return NavigationActionPolicy.CANCEL;
              },
            ),
          ),
          _quickBar(context, scheme),
        ],
      ),
    );
  }

  /// 底部快捷入口：站内几个固定页面，省得每次都从首页点进去。
  Widget _quickBar(BuildContext context, ColorScheme scheme) {
    final links = _site.quickLinks;
    if (links.isEmpty) return const SizedBox.shrink();
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          height: 56,
          decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)))),
          child: Row(
            children: [
              for (final link in links)
                Expanded(
                  child: InkWell(
                    onTap: () => _go(link.path),
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
}

/// 注入到站点页面里的小修补。
///
/// 只做三件不改站点结构的事：把内联的「打开 App」横幅和 Cookie 提示收掉、
/// 把新窗口链接改成当前窗口打开（否则在 WebView 里点了没反应）、关掉
/// iOS 风格的自动字号放大。选择器都按 XenForo 的稳定类名写，命中不了
/// 也只是没生效。
const String _tweakScript = r'''
(function () {
  try {
    var id = 'mtforum-site-tweaks';
    if (!document.getElementById(id)) {
      var style = document.createElement('style');
      style.id = id;
      style.textContent = [
        'html{-webkit-text-size-adjust:100%;}',
        '.notice--cookie,.notice--cookieAdvanced,[data-xf-init~="cookie-notice"]{display:none!important;}',
        '.smartbanner,.smart-banner,#smartbanner,[class*="app-banner"],[id*="app-banner"]{display:none!important;}'
      ].join('');
      (document.head || document.documentElement).appendChild(style);
    }
    var links = document.querySelectorAll('a[target="_blank"]');
    for (var i = 0; i < links.length; i++) {
      links[i].removeAttribute('target');
    }
  } catch (e) {}
})();
''';
