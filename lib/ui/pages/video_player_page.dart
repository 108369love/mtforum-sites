import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_webview_flutter/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/video_link.dart';

/// 应用内视频播放页。
///
/// B站 / YouTube 用官方 iframe 播放器，直链文件自己包一层 <video>，
/// 其他站点则直接用内置浏览器打开原页面 —— 全程不跳出应用。
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.video, this.title});

  final VideoLink video;
  final String? title;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  int _progress = 0;
  String? _error;

  /// 播放器页面用移动端 Chrome UA：论坛自定义 UA 会被视频站当成爬虫挡掉。
  static const String _playerUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  @override
  void initState() {
    super.initState();
    // 视频大多横屏观看，进页面就允许旋转，退出时还原。
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.video.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 底栏展示的来源，用原始链接而不是 iframe 播放器地址。
  String get _sourceLabel {
    final uri = Uri.tryParse(widget.video.url);
    if (uri == null || uri.host.isEmpty) return widget.video.url;
    final path = uri.path.length > 40 ? '${uri.path.substring(0, 40)}…' : uri.path;
    return '${uri.host}$path';
  }

  String get _pageTitle {    final custom = widget.title?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final id = widget.video.videoId;
    return id == null ? '${widget.video.kind.label}播放' : '${widget.video.kind.label} · $id';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            tooltip: '用浏览器打开',
            icon: const Icon(Icons.open_in_browser_rounded, size: 20),
            onPressed: _openExternal,
          ),
        ],
        bottom: _progress > 0 && _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100, minHeight: 2),
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _webview(context)),
                if (_error != null) _errorOverlay(context, _error!),
              ],
            ),
          ),
          _footBar(context),
        ],
      ),
    );
  }

  Widget _webview(BuildContext context) {
    final video = widget.video;
    if (video.isDirectFile) {
      return InAppWebView(
        initialSettings: _settings(),
        onWebViewCreated: (controller) async {
          await controller.loadData(
            data: _directHtml(video.playUrl),
            mimeType: 'text/html',
            encoding: 'utf8',
            baseUrl: WebUri(AppConfig.base),
          );
        },
        onProgressChanged: _onProgress,
      );
    }
    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(video.playUrl),
        headers: {'User-Agent': _playerUserAgent},
      ),
      initialSettings: _settings(),
      onProgressChanged: _onProgress,
      onReceivedHttpError: (controller, request, response) {
        final status = response.statusCode ?? 0;
        if (status >= 400 && mounted) {
          setState(() => _error = '播放器返回 $status，可能是不允许站外播放。可点右上角用浏览器打开。');
        }
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame == true && mounted) {
          setState(() => _error = '无法加载播放器：${error.description}');
        }
      },
    );
  }

  void _onProgress(InAppWebViewController controller, int progress) {
    if (!mounted) return;
    setState(() => _progress = progress);
  }

  InAppWebViewSettings _settings() => InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        thirdPartyCookiesEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        useHybridComposition: true,
        supportMultipleWindows: false,
        useShouldOverrideUrlLoading: false,
      );

  /// 直链视频（mp4 / m3u8 …）包一层整屏 <video>。
  String _directHtml(String src) {
    final isHls = src.toLowerCase().contains('.m3u8');
    final hls = isHls
        ? '''
    <script src="https://cdn.jsdelivr.net/npm/hls.js@1"></script>
    <script>
      (function () {
        var v = document.getElementById('v');
        if (window.Hls && window.Hls.isSupported()) {
          var hls = new Hls({ enableWorker: true });
          hls.loadSource("${_jsString(src)}");
          hls.attachMedia(v);
          hls.on(Hls.Events.ERROR, function (e, data) {
            if (data && data.fatal) { document.getElementById('tip').style.display = 'block'; }
          });
          v.play().catch(function () {});
        }
      })();
    </script>'''
        : '';
    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <style>
    html, body { margin: 0; height: 100%; background: #000; }
    #wrap { height: 100%; display: flex; align-items: center; justify-content: center; }
    video { width: 100%; height: 100%; object-fit: contain; background: #000; }
    #tip { position: fixed; left: 0; right: 0; bottom: 16px; text-align: center;
           color: #bbb; font: 13px/1.6 -apple-system, "PingFang SC", sans-serif; display: none; }
  </style>
</head>
<body>
  <div id="wrap">
    <video id="v" src="${_jsString(src)}" controls autoplay playsinline webkit-playsinline preload="metadata"></video>
  </div>
  <div id="tip">这个视频格式无法直接播放，可用右上角「用浏览器打开」</div>
  $hls
</body>
</html>
''';
  }

  /// HTML 属性里只转义必要的字符，避免把 URL 里的 & 变成 &amp; 后失效。
  String _jsString(String value) => value.replaceAll('&', '&amp;').replaceAll('"', '&quot;');

  Widget _errorOverlay(BuildContext context, String message) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, size: 18, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 12.5, height: 1.5, color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        color: const Color(0xFF141414),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Icon(Icons.movie_outlined, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _sourceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: Colors.white38),
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: _openExternal,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: Colors.white70,
              ),
              child: const Text('浏览器', style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }
}
