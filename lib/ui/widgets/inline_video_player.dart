import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// 正文里就地播放的视频。
///
/// 点开播放区域后视频直接在帖子里展开播放，不再跳到单独的页面。
/// 全屏按钮会把同一个 controller 交给 [FullscreenVideoPage]，播放进度不中断。
class InlineVideoPlayer extends StatefulWidget {
  const InlineVideoPlayer({
    super.key,
    required this.url,
    this.onFullscreen,
    this.onOpenExternal,
  });

  final String url;
  final void Function(VideoPlayerController controller)? onFullscreen;
  final VoidCallback? onOpenExternal;

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.play();
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(() {});
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _failure(context);
    }
    final controller = _controller;
    if (_loading || controller == null || !controller.value.isInitialized) {
      return const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white70)));
    }
    return _VideoStage(
      controller: controller,
      onFullscreen: widget.onFullscreen,
      onOpenExternal: widget.onOpenExternal,
    );
  }

  Widget _failure(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off_outlined, size: 26, color: Colors.white54),
          const SizedBox(height: 8),
          const Text('这个视频无法直接播放', style: TextStyle(fontSize: 12.5, color: Colors.white70)),
          if (widget.onOpenExternal != null) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: widget.onOpenExternal,
              style: TextButton.styleFrom(foregroundColor: Colors.white70, minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 10)),
              child: const Text('用浏览器打开', style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 播放画面 + 控制条，正文内与全屏页共用。
class _VideoStage extends StatefulWidget {
  const _VideoStage({required this.controller, this.onFullscreen, this.onOpenExternal});

  final VideoPlayerController controller;
  final void Function(VideoPlayerController controller)? onFullscreen;
  final VoidCallback? onOpenExternal;

  @override
  State<_VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends State<_VideoStage> {
  bool _controls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.controller.value.isPlaying) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _togglePlay() {
    final value = widget.controller.value;
    if (value.isCompleted) {
      widget.controller.seekTo(Duration.zero);
      widget.controller.play();
    } else if (value.isPlaying) {
      widget.controller.pause();
      setState(() => _controls = true);
    } else {
      widget.controller.play();
      _scheduleHide();
    }
  }

  String _fmt(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
                child: VideoPlayer(widget.controller),
              ),
            ),
            // 点画面切控制条；播放中隐藏控制条时不挡任何手势。
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                child: AnimatedOpacity(
                  opacity: _controls ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Container(
                    color: Colors.black26,
                    alignment: Alignment.center,
                    child: IgnorePointer(
                      ignoring: !_controls,
                      child: IconButton(
                        onPressed: _togglePlay,
                        iconSize: 46,
                        color: Colors.white,
                        icon: Icon(
                          value.isCompleted
                              ? Icons.replay_rounded
                              : value.isPlaying
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_controls)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 16, 6, 4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${_fmt(value.position)} / ${_fmt(value.duration)}',
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: VideoProgressIndicator(
                          widget.controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white30, backgroundColor: Colors.white24),
                        ),
                      ),
                      if (widget.onFullscreen != null)
                        IconButton(
                          tooltip: '全屏',
                          onPressed: () => widget.onFullscreen!(widget.controller),
                          icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 22),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 全屏播放：复用正文里那个 controller，退出全屏继续在正文位置播放。
class FullscreenVideoPage extends StatefulWidget {
  const FullscreenVideoPage({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  State<FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<FullscreenVideoPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _VideoStage(controller: widget.controller),
          ),
          Positioned(
            left: 4,
            top: 4,
            child: SafeArea(
              child: IconButton(
                tooltip: '退出全屏',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
