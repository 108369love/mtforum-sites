import 'package:flutter/material.dart';

import 'thread_glass.dart';

/// 玻璃对话框：一块模糊 + 半透明渐变的卡片。
///
/// 没有直接包 [AlertDialog]：`AlertDialog` 内部是「全屏 `AnimatedPadding` +
/// 居中 `Align`」，把它塞进 [GlassBackdrop] 会让玻璃底板被撑满整块屏幕，
/// 整页糊成一片。这里照 [AlertDialog] 的 M3 尺寸自己排一份：标题 22、正文
/// 15、底部一排靠右的动作按钮，和系统对话框观感一致。
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.scrollable = false,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  /// 内容超长时滚动（默认跟随屏幕高度收缩）。
  final bool scrollable;

  static const EdgeInsets _inset = EdgeInsets.symmetric(horizontal: 34, vertical: 24);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasActions = actions != null && actions!.isNotEmpty;

    // 对话框和顶栏、回复框不是一类东西：那两处是「从上面掠过」，透一点没关系；
    // 这里是要人逐字读的一段话，背后往往还是一张彩色封面。而全局玻璃不透明度
    // 可调到 0.05，用户一旦调低，正文就等于直接写在背景图上——再怎么加深文字
    // 颜色也救不回来。所以这里压一个下限，只保住对话框，不动全局设置。
    final glassOpacity = ThreadGlass.opacity;
    final glassBlur = ThreadGlass.blur;
    final dialogOpacity = glassOpacity < 0.8 ? 0.8 : glassOpacity;
    final dialogBlur = glassBlur < 20 ? 20.0 : glassBlur;

    Widget column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: 17.5,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: scheme.onSurface,
            ),
            child: title!,
          ),
        if (title != null && content != null) const SizedBox(height: 12),
        if (content != null)
          DefaultTextStyle.merge(
            style: TextStyle(
              // 中文正文 14 在手机上偏紧，尤其是两行以上连续阅读。
              fontSize: 15,
              height: 1.5,
              // 用不带任何透明度、亮度也拉满的 onSurface：对话框底下是玻璃，
              // 任何 alpha 都会被背景再稀释一层，读起来发灰。
              color: scheme.onSurface,
            ),
            child: content!,
          ),
        if (hasActions) ...[
          const SizedBox(height: 18),
          _actionBar(context, actions!),
        ],
      ],
    );

    if (scrollable) {
      column = SingleChildScrollView(child: column);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      insetPadding: _inset,
      child: GlassBackdrop(
        borderRadius: BorderRadius.circular(22),
        showShadow: true,
        opacityScale: 1.12,
        opacity: dialogOpacity,
        blur: dialogBlur,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 268,
            maxWidth: MediaQuery.sizeOf(context).width - _inset.horizontal,
            maxHeight: MediaQuery.sizeOf(context).height - _inset.vertical,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(22, 21, 22, hasActions ? 18 : 21),
            child: column,
          ),
        ),
      ),
    );
  }

  /// 动作区。
  ///
  /// 之前是 OverflowBar 右对齐：一个纯文字「取消」挨着一个填充胶囊「确定踢帖」，
  /// 两种形状、两种高度并排，右边那颗又几乎顶到卡片边，看着像临时拼上去的。
  /// 两个按钮时改成等宽并排、同高同圆角，靠底色分主次；一个或三个按钮仍右对齐。
  Widget _actionBar(BuildContext context, List<Widget> actions) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(14);

    return Theme(
      data: theme.copyWith(
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: scheme.onSurface,
            backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
            minimumSize: const Size.fromHeight(46),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: radius),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: radius),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      child: actions.length == 2
          ? Row(
              children: [
                Expanded(child: actions[0]),
                const SizedBox(width: 10),
                Expanded(child: actions[1]),
              ],
            )
          : OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 10,
              overflowSpacing: 8,
              children: actions,
            ),
    );
  }
}

/// 弹出玻璃对话框。[builder] 里通常返回 [GlassDialog]。
///
/// 和 `showDialog` 的调用方式一致，只是遮罩更淡（玻璃要看得到背后的内容）、
/// 进场是淡入 + 轻微放大。
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel ?? '关闭对话框',
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.42),
    transitionDuration: const Duration(milliseconds: 180),
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    pageBuilder: (dialogContext, _, __) => builder(dialogContext),
    transitionBuilder: (dialogContext, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
