import 'dart:ui';

import 'package:flutter/material.dart';

import '../../state/app_state.dart';

/// 帖子页三处玻璃（顶栏、底部回复框、右上角菜单）共用的取色与取值。
///
/// 三处读的是同一组配置，这样顶栏和回复框不会一半透明一半发实。
class ThreadGlass {
  const ThreadGlass._();

  /// 玻璃底色的不透明度。
  static double get opacity => AppState.instance.threadGlassOpacity;

  /// 背景高斯模糊强度。
  static double get blur => AppState.instance.threadGlassBlur;

  /// 左上亮、右下暗的渐变，模拟光线斜穿玻璃。
  ///
  /// [opacityScale] 用于局部微调：顶栏要压住标题，回复框可以更透一点。
  static LinearGradient gradient(
    BuildContext context, {
    double opacityScale = 1,
    double? opacityOverride,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final alpha = ((opacityOverride ?? opacity) * opacityScale).clamp(0.0, 1.0).toDouble();
    final top = isDark ? const Color(0xFF303945) : Colors.white;
    final bottom = isDark ? const Color(0xFF171D26) : const Color(0xFFF1F5FA);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        top.withValues(alpha: alpha),
        bottom.withValues(alpha: alpha * 0.72),
      ],
    );
  }

  /// 描边色：浅色主题用淡灰，深色主题用半透明白，避免玻璃边缘糊成一片。
  static Color borderColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return (isDark ? Colors.white : scheme.outlineVariant)
        .withValues(alpha: isDark ? 0.18 : 0.32);
  }
}

/// 一块玻璃底板：背景高斯模糊 + 半透明渐变。
///
/// 模糊的是「已经画在它下面的东西」，所以调用方要保证内容确实从它背后
/// 掠过——顶栏靠 `extendBodyBehindAppBar`，回复框靠自己浮在列表上层。
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.opacityScale = 1,
    this.showBorder = true,
    this.showShadow = false,
    this.blur,
    this.opacity,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// 透明度倍数，用于局部加深或减淡。
  final double opacityScale;
  final bool showBorder;
  final bool showShadow;

  /// 指定模糊强度；为空时取全局设置。
  final double? blur;

  /// 指定透明度；为空时取全局设置。设置面板的预览要用草稿值，不能走全局。
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final sigma = blur ?? ThreadGlass.blur;
        return ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: ThreadGlass.gradient(
                  context,
                  opacityScale: opacityScale,
                  opacityOverride: opacity,
                ),
                border: showBorder ? Border.all(color: ThreadGlass.borderColor(context)) : null,
                boxShadow: showShadow
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: Theme.of(context).brightness == Brightness.dark ? 0.30 : 0.14,
                          ),
                          blurRadius: 26,
                          offset: const Offset(0, 12),
                        ),
                      ]
                    : null,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
