import 'package:flutter/material.dart';

/// 平滑滚回顶部。
///
/// 已经在顶部时直接返回，不播一段空动画，免得双击像点了没反应又像抖了一下。
Future<void> scrollToTop(ScrollController controller) async {
  if (!controller.hasClients) return;
  if (controller.position.pixels <= 8) return;
  await controller.animateTo(
    0,
    duration: const Duration(milliseconds: 320),
    curve: Curves.easeOutCubic,
  );
}

/// 顶栏的空白区域：双击回顶。
///
/// 放进 [AppBar.flexibleSpace]，它铺在标题和按钮下面一层，
/// 所以只有没被返回键、标题、右侧图标占住的空白处会落到这里，
/// 按钮本身的单击行为不受影响。只认双击，单击不做任何事。
class DoubleTapTopArea extends StatelessWidget {
  const DoubleTapTopArea({super.key, required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () => scrollToTop(controller),
      child: const SizedBox.expand(),
    );
  }
}
