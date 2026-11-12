import 'package:flutter/material.dart';

/// 测出子组件的实际高度，变化时回调。
///
/// 悬浮的玻璃条（帖子回复框、私信输入条、发帖工具条、搜索条）都得向下层
/// 列表让出高度。这个高度由内容决定：输入框换行、表情面板展开、分类下拉
/// 出现都会变。写死一个常数只能赌：估小了最后一条内容被压在玻璃底下，
/// 估大了底部多出一块没用的空白。
class MeasureHeight extends StatefulWidget {
  const MeasureHeight({super.key, required this.onHeight, required this.child});

  final ValueChanged<double> onHeight;
  final Widget child;

  @override
  State<MeasureHeight> createState() => _MeasureHeightState();
}

class _MeasureHeightState extends State<MeasureHeight> {
  final _key = GlobalKey();
  double? _reported;

  @override
  void initState() {
    super.initState();
    // 首帧才知道真实尺寸，不能在 build 里读。
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final height = box.size.height;
    // 半像素内的抖动不回调，否则每帧都会顶着重构父页面。
    if (_reported != null && (height - _reported!).abs() < 0.5) return;
    _reported = height;
    widget.onHeight(height);
  }

  @override
  Widget build(BuildContext context) {
    // 子组件自己长高（输入框换行）不会触发祖先布局变化通知，
    // 但 SizeChangedLayoutNotifier 会在自身尺寸变化后补一次回调。
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: KeyedSubtree(key: _key, child: widget.child),
      ),
    );
  }
}
