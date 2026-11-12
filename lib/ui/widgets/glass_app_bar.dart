import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_state.dart';
import 'back_to_top.dart';
import 'thread_glass.dart';

/// 透明玻璃顶栏。
///
/// 和帖子页顶栏同一套取色：底色透明，正文从 `flexibleSpace` 里那块玻璃背后
/// 滚过，模糊才有内容可糊。
///
/// 用它的页面必须同时做两件事，缺一件就会露馅：
/// 1. `Scaffold.extendBodyBehindAppBar: true`，否则 body 从顶栏下沿开始，
///    玻璃背后什么都没有；
/// 2. 列表顶部补 [glassTopInset] 的留白，否则第一条内容被顶栏压住。
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.doubleTapController,
    this.automaticallyImplyLeading = true,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  /// 传入滚动控制器后，顶栏空白处双击回顶。标题和按钮在上层，不受影响。
  final ScrollController? doubleTapController;

  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      leading: leading,
      actions: actions,
      bottom: bottom,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      // 背景透明时 AppBar 会把透明当成「很暗」，浅色主题下状态栏图标会变白。
      systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      flexibleSpace: Stack(
        fit: StackFit.expand,
        children: [
          GlassBackdrop(
            showBorder: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: ThreadGlass.borderColor(context), width: 0.6),
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          if (doubleTapController != null) DoubleTapTopArea(controller: doubleTapController!),
        ],
      ),
    );
  }
}

/// 二级页面统一的左右边距。
///
/// 之前每个页面各写各的：14 / 16 / 12 / 20 / 18 都出现过，同一个列表在不同
/// 页面之间左右会跳几像素。以主路径用得最多的 14 为准。
const double kPageGutter = 14;

/// 玻璃页面正文的默认内边距：左右 [kPageGutter]，顶部空出玻璃顶栏。
EdgeInsets glassPagePadding(
  BuildContext context, {
  double top = 8,
  double bottom = 24,
  double gutter = kPageGutter,
  double appBarBottom = 0,
}) =>
    EdgeInsets.fromLTRB(
      gutter,
      glassTopInset(context, bottomHeight: appBarBottom) + top,
      gutter,
      bottom,
    );

/// 玻璃顶栏下正文需要空出的高度：状态栏 + 顶栏（含 [TabBar] 这类 bottom）。
double glassTopInset(BuildContext context, {double bottomHeight = 0}) =>
    MediaQuery.paddingOf(context).top + kToolbarHeight + bottomHeight;

/// 悬浮玻璃底栏占掉的屏幕高度，列表末尾要补这么多。
///
/// 底栏走 `Scaffold.extendBody`，浮在内容之上并不占位。补少了，最后一张卡片
/// 会被压进底栏里面：白色卡片和卡片外浅灰背景的分界横穿胶囊，玻璃背后是白，
/// 模糊完还是白，那块看起来就像「没有玻璃」；补多了又会在胶囊顶边上方露出
/// 一条背景色的缝。
///
/// 高度优先取 AppShell 实测值（[AppState.floatingNavHeight]），量不到时
/// 退回「胶囊 66 + 底部安全区，SafeArea 的 minimum 是 10」。末尾再减几个
/// 像素，让最后一项略微延续到玻璃背后：宁可被压住一点，也不要在胶囊顶边
/// 上方留一条背景色的缝。
double floatingNavSpace(BuildContext context) {
  if (!AppState.instance.floatingGlassNav) return 0;
  // 优先用 AppShell 量出来的真实高度：系统字号调大时胶囊会变高，
  // 任何写死的常数都会偏。
  final measured = AppState.instance.floatingNavHeight;
  if (measured > 0) return measured - 2;
  final safe = MediaQuery.paddingOf(context).bottom;
  return 66 + (safe > 10 ? safe : 10) - 6;
}
