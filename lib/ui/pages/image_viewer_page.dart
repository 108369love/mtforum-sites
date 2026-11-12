import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../../core/native_bridge.dart';

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({super.key, required this.images, this.initialIndex = 0});

  final List<String> images;
  final int initialIndex;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _saving = false;

  /// 每张图各带一个变换控制器，用来判断当前有没有放大。
  final Map<int, TransformationController> _transforms = <int, TransformationController>{};

  /// 下滑关闭的位移与状态。
  double _dragOffset = 0;
  bool _dragging = false;
  Offset? _pointerStart;

  double get _currentScale => _transforms[_index]?.value.getMaxScaleOnAxis() ?? 1.0;

  @override
  void dispose() {
    _controller.dispose();
    for (final controller in _transforms.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------- 下滑关闭
  //
  // 系统返回手势只认屏幕左右那条边缘，而翻图也吃同一片横向区域：想关页面
  // 时从边缘滑，想翻回上一张时也从边缘滑，两者抢同一串指针。给一个不依赖
  // 边缘的关闭方式，横向整片留给翻页、边缘留给系统，各走各的。
  //
  // 用 Listener 而不是 GestureDetector：Listener 只看指针、不进手势竞技场，
  // 不会把 PageView 的横向拖动或 InteractiveViewer 的缩放抢走。放大状态下
  // 不接管——那时的拖动是在平移图片。

  bool get _canDragToDismiss => _currentScale <= 1.01;

  void _onPointerDown(PointerDownEvent event) {
    if (!_canDragToDismiss) {
      _pointerStart = null;
      return;
    }
    _pointerStart = event.position;
    _dragging = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final start = _pointerStart;
    if (start == null) return;
    final delta = event.position - start;
    if (!_dragging) {
      // 竖向位移要明显压过横向才接管，否则翻页起手就被判成关闭。
      if (delta.dy < 10 || delta.dy < delta.dx.abs() * 1.6) return;
    }
    if (!_canDragToDismiss) return;
    final next = delta.dy.clamp(0.0, 600.0);
    if (_dragging && (next - _dragOffset).abs() < 0.5) return;
    // 接管的第一帧就要把 _dragging 打开：AnimatedContainer 的时长由它决定，
    // 晚一帧切换就会看到图片先慢吞吞跟上来。
    setState(() {
      _dragging = true;
      _dragOffset = next;
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointerStart = null;
    if (!_dragging) return;
    final moved = _dragOffset;
    setState(() {
      _dragging = false;
      _dragOffset = 0;
    });
    // 拖过屏幕高度的 18% 就关，否则回弹——和多数看图应用的手感一致。
    if (moved > MediaQuery.sizeOf(context).height * 0.18) {
      Navigator.of(context).pop();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointerStart = null;
    if (!_dragging) return;
    setState(() {
      _dragging = false;
      _dragOffset = 0;
    });
  }

  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = widget.images[_index];
      late final Uint8List bytes;
      final uri = Uri.parse(url);
      if (uri.scheme == 'file') {
        bytes = await File(uri.toFilePath()).readAsBytes();
      } else {
        final client = HttpClient();
        try {
          final request = await client.getUrl(uri);
          request.headers.set('Referer', AppConfig.base);
          request.headers.set('User-Agent', AppConfig.userAgent);
          final cookie = HttpSession.instance.cookieHeader;
          if (cookie.isNotEmpty) request.headers.set('Cookie', cookie);
          final response = await request.close();
          if (response.statusCode != HttpStatus.ok) {
            throw Exception('图片下载失败（${response.statusCode}）');
          }
          final builder = BytesBuilder(copy: false);
          await for (final chunk in response) {
            builder.add(chunk);
          }
          bytes = builder.takeBytes();
        } finally {
          client.close();
        }
      }
      final ok = await NativeBridge.saveImage(
        bytes,
        name: 'mt_forum_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      messenger.showSnackBar(SnackBar(content: Text(ok ? '已保存到相册' : '保存失败，请检查存储权限')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _image(int index, String cookie) {
    return widget.images[index].startsWith('file://')
        ? Image.file(
            File(Uri.parse(widget.images[index]).toFilePath()),
            fit: BoxFit.contain,
          )
        : Image.network(
            widget.images[index],
            headers: {
              'Referer': AppConfig.base,
              'User-Agent': AppConfig.userAgent,
              if (cookie.isNotEmpty) 'Cookie': cookie,
            },
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 46),
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2),
                  ),
          );
  }

  @override
  Widget build(BuildContext context) {
    final cookie = HttpSession.instance.cookieHeader;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: AnimatedContainer(
            // 拖动中必须 0：留一帧过渡都会觉得图片黏手。只有回弹才要动画。
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, _dragOffset, 0),
            child: Stack(
              children: [
                PageView.builder(
                  controller: _controller,
                  itemCount: widget.images.length,
                  onPageChanged: (index) => setState(() => _index = index),
                  itemBuilder: (context, index) => InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    transformationController:
                        _transforms.putIfAbsent(index, TransformationController.new),
                    child: Center(child: _image(index, cookie)),
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_index + 1} / ${widget.images.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.of(context).padding.bottom + 18,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _saving ? null : _saveToGallery,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white70,
                                ),
                              )
                            : const Icon(Icons.download_rounded, color: Colors.white70),
                        label: const Text('保存到相册', style: TextStyle(color: Colors.white70)),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: widget.images[_index]));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('图片链接已复制')),
                          );
                        },
                        icon: const Icon(Icons.link_rounded, color: Colors.white70),
                        label: const Text('复制图片链接', style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
