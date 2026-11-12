import 'package:flutter/material.dart';
import 'package:in_app_webview_flutter/flutter_inappwebview.dart';
import 'package:video_player/video_player.dart';

import '../../core/video_link.dart';
import '../pages/video_player_page.dart';
import 'inline_video_player.dart';
import 'smart_image.dart';
import '../navigation/app_routes.dart';

/// 正文里的视频播放区域。
///
/// 点击后视频就在帖子里展开播放（直链用原生播放器，B站/YouTube 用内嵌播放器），
/// 不跳页面、不离开正文；需要大屏时再点全屏。
class VideoCard extends StatefulWidget {
  const VideoCard({
    super.key,
    required this.video,
    this.cover,
    this.title,
    this.onOpenExternal,
  });

  final VideoLink video;

  /// 可选封面（B站视频封面等）。为空时用来源色渐变占位。
  final String? cover;

  /// 卡片标题，默认「视频演示」。
  final String? title;

  /// 「用浏览器打开」的兜底回调。
  final VoidCallback? onOpenExternal;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  /// 同一时刻只允许一个视频在正文里播放，展开新的会把旧的收起来。
  static final ValueNotifier<int?> _active = ValueNotifier<int?>(null);

  bool _expanded = false;
  int get _id => identityHashCode(this);

  @override
  void initState() {
    super.initState();
    _active.addListener(_onActiveChanged);
  }

  @override
  void dispose() {
    _active.removeListener(_onActiveChanged);
    if (_active.value == _id) _active.value = null;
    super.dispose();
  }

  void _onActiveChanged() {
    if (_expanded && _active.value != _id && mounted) {
      setState(() => _expanded = false);
    }
  }

  void _expand() {
    if (_expanded) return;
    setState(() => _expanded = true);
    _active.value = _id;
  }

  void _collapse() {
    if (!_expanded) return;
    if (_active.value == _id) _active.value = null;
    setState(() => _expanded = false);
  }

  void _openFullscreen(VideoPlayerController controller) {
    Navigator.of(context).push(appRoute(
      builder: (_) => FullscreenVideoPage(controller: controller),
    ));
  }

  void _openStandalone() {
    Navigator.of(context).push(appRoute(
      builder: (_) => VideoPlayerPage(video: widget.video, title: widget.title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _accent(widget.video.kind);

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _expanded ? _player(accent) : _cover(scheme, accent),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    Icon(Icons.movie_outlined, size: 17, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title ?? '视频演示',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w600, color: scheme.onSurface),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _expanded ? '正在正文中播放' : widget.video.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, height: 1.3, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (_expanded)
                      TextButton(
                        onPressed: _collapse,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('收起', style: TextStyle(fontSize: 12.5)),
                      )
                    else
                      Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _player(Color accent) {
    if (widget.video.isDirectFile) {
      return ColoredBox(
        color: Colors.black,
        child: InlineVideoPlayer(
          url: widget.video.playUrl,
          onFullscreen: _openFullscreen,
          onOpenExternal: widget.onOpenExternal,
        ),
      );
    }
    return _InlineWebVideo(video: widget.video, onOpenStandalone: _openStandalone);
  }

  Widget _cover(ColorScheme scheme, Color accent) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.cover != null && widget.cover!.isNotEmpty)
          SmartImage(url: widget.cover!, fit: BoxFit.cover, radius: BorderRadius.zero)
        else
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(accent.withValues(alpha: 0.55), const Color(0xFF14161C)),
                  const Color(0xFF14161C),
                ],
              ),
            ),
          ),
        // 压暗一层，保证播放按钮和标签在任何封面上都清楚。
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0x66000000)],
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _expand,
            child: Center(
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 4)),
                  ],
                ),
                child: Icon(Icons.play_arrow_rounded, size: 36, color: accent),
              ),
            ),
          ),
        ),
        Positioned(
          left: 10,
          top: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.video.kind.label,
              style: const TextStyle(fontSize: 11, height: 1.2, color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        if (widget.video.videoId != null)
          Positioned(
            right: 10,
            bottom: 10,
            child: Text(
              widget.video.videoId!,
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8)),
            ),
          ),
        if (widget.onOpenExternal != null)
          Positioned(
            right: 6,
            top: 6,
            child: IconButton(
              tooltip: '用浏览器打开',
              onPressed: widget.onOpenExternal,
              icon: const Icon(Icons.open_in_browser_rounded, size: 18, color: Colors.white70),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
      ],
    );
  }

  static Color _accent(VideoKind kind) {
    switch (kind) {
      case VideoKind.bilibili:
        return const Color(0xFFFB7299);
      case VideoKind.youtube:
        return const Color(0xFFFF0033);
      case VideoKind.douyin:
        return const Color(0xFF25F4EE);
      case VideoKind.kuaishou:
        return const Color(0xFFFF7A00);
      case VideoKind.ixigua:
        return const Color(0xFFFF4B4B);
      case VideoKind.tencent:
        return const Color(0xFF2AA3FF);
      case VideoKind.youku:
        return const Color(0xFF1AA9E0);
      case VideoKind.acfun:
        return const Color(0xFFFD4C5D);
      case VideoKind.weibo:
        return const Color(0xFFE6162D);
      case VideoKind.direct:
      case VideoKind.other:
        return const Color(0xFF5B8DEF);
    }
  }
}

/// B站 / YouTube / 站点页面这类只能用网页播放器的源，在正文里内嵌一个 WebView。
class _InlineWebVideo extends StatelessWidget {
  const _InlineWebVideo({required this.video, required this.onOpenStandalone});

  final VideoLink video;
  final VoidCallback onOpenStandalone;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(video.playUrl),
              headers: const {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 13; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
              },
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              thirdPartyCookiesEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              useHybridComposition: true,
              supportMultipleWindows: false,
            ),
          ),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: IconButton(
            tooltip: '放大播放',
            onPressed: onOpenStandalone,
            icon: const Icon(Icons.open_in_full_rounded, size: 18, color: Colors.white70),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ),
      ],
    );
  }
}
