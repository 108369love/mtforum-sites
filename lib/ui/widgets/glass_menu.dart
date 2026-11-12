import 'package:flutter/material.dart';

import 'thread_glass.dart';

/// 一条玻璃菜单项。
///
/// [value] 会通过 [showGlassMenu] 的返回值原样带出来，调用方按值分发动作。
@immutable
class GlassMenuItem<V> {
  const GlassMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.danger = false,
    this.enabled = true,
  });

  final V value;
  final String label;
  final IconData? icon;

  /// 危险动作（删除、封禁）用错误色，和普通项拉开距离。
  final bool danger;

  /// 不可点时文字压灰，点击无响应。
  final bool enabled;
}

/// 在 [anchor] 旁边弹出一块玻璃菜单，返回选中项的值。
///
/// 定位规则和系统弹出菜单一致：默认贴在锚点下方、右边缘对齐；下方放不下
/// 就翻到上边；两侧越界则夹回屏幕内。整块菜单会限制在安全区内，项数多时
/// 内部滚动，不会顶出屏幕。
///
/// 视觉上是一块模糊 + 半透明渐变的玻璃卡片，取代 Material 那块不透明的
/// [PopupMenuButton] 底板。
Future<V?> showGlassMenu<V>(
  BuildContext context, {
  required Rect anchor,
  required List<GlassMenuItem<V>> items,
  double width = 218,
  bool dividers = false,
  String barrierLabel = '菜单',
}) {
  if (items.isEmpty) return Future<V?>.value();
  return showGeneralDialog<V>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.06),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (dialogContext, _, __) => _GlassMenuOverlay<V>(
      anchor: anchor,
      items: items,
      width: width,
      dividers: dividers,
    ),
    transitionBuilder: (dialogContext, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      final screen = MediaQuery.sizeOf(dialogContext);
      final safe = MediaQuery.paddingOf(dialogContext);
      // 只影响缩放的原点，和最终定位无关，所以这里用估算高度就够。
      final estimate = items.length * 42 + 12;
      final below = anchor.bottom + 6 + estimate <= screen.height - safe.bottom - 8;
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          alignment: below ? Alignment.topRight : Alignment.bottomRight,
          child: child,
        ),
      );
    },
  );
}

class _GlassMenuOverlay<V> extends StatelessWidget {
  const _GlassMenuOverlay({
    required this.anchor,
    required this.items,
    required this.width,
    required this.dividers,
  });

  final Rect anchor;
  final List<GlassMenuItem<V>> items;
  final double width;
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final safe = MediaQuery.paddingOf(context);
    final screen = MediaQuery.sizeOf(context);
    const radius = 18.0;

    final card = ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: screen.height - safe.top - safe.bottom - 16,
      ),
      child: GlassBackdrop(
        borderRadius: BorderRadius.circular(radius),
        showShadow: true,
        opacityScale: 1.06,
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (dividers && i > 0)
                      Divider(
                        height: 0.6,
                        thickness: 0.6,
                        color: scheme.outlineVariant.withValues(alpha: 0.26),
                      ),
                    _MenuRow<V>(item: items[i]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: CustomSingleChildLayout(
        delegate: _MenuLayout(anchor: anchor, safe: safe),
        child: card,
      ),
    );
  }
}

class _MenuRow<V> extends StatelessWidget {
  const _MenuRow({required this.item});

  final GlassMenuItem<V> item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = item.danger ? scheme.error : scheme.onSurfaceVariant;
    final fg = item.enabled ? base : base.withValues(alpha: 0.4);
    return InkWell(
      onTap: item.enabled ? () => Navigator.of(context).pop(item.value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        child: Row(
          children: [
            if (item.icon != null) ...[
              Icon(item.icon, size: 18.5, color: fg),
              const SizedBox(width: 11),
            ],
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: item.enabled
                      ? (item.danger ? scheme.error : scheme.onSurface)
                      : scheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 贴着锚点摆放，放不下就翻边。
class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout({required this.anchor, required this.safe});

  final Rect anchor;
  final EdgeInsets safe;

  static const double _gap = 6;
  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = _margin + safe.left;
    final right = size.width - _margin - safe.right - childSize.width;
    var x = anchor.right - childSize.width;
    x = right < left ? left : x.clamp(left, right);

    final top = _margin + safe.top;
    final bottom = size.height - _margin - safe.bottom - childSize.height;
    var y = anchor.bottom + _gap;
    if (y > bottom) {
      final above = anchor.top - _gap - childSize.height;
      y = above >= top ? above : bottom;
    }
    if (y < top) y = top;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      oldDelegate.anchor != anchor || oldDelegate.safe != safe;
}

/// 一个「更多」触发按钮 + 玻璃菜单。
///
/// 替代 [PopupMenuButton]：外观是一个普通图标按钮，点开的是玻璃浮层。
class GlassMenuButton<V> extends StatelessWidget {
  const GlassMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.icon = Icons.more_horiz_rounded,
    this.iconSize = 19,
    this.color,
    this.tooltip,
    this.padding = EdgeInsets.zero,
    this.dividers = false,
    this.menuWidth = 218,
    this.hitSize = 40,
  });

  final List<GlassMenuItem<V>> items;
  final ValueChanged<V> onSelected;
  final IconData icon;
  final double iconSize;
  final Color? color;
  final String? tooltip;
  final EdgeInsets padding;
  final bool dividers;
  final double menuWidth;

  /// 触发区的边长，决定点击热区和锚点大小。
  final double hitSize;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final picked = await showGlassMenu<V>(
      context,
      anchor: anchor,
      items: items,
      width: menuWidth,
      dividers: dividers,
      barrierLabel: tooltip ?? '菜单',
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = Builder(
      builder: (inner) => InkResponse(
        onTap: () => _open(inner),
        radius: hitSize / 2,
        child: SizedBox(
          width: hitSize,
          height: hitSize,
          child: Icon(icon, size: iconSize, color: color ?? scheme.outline),
        ),
      ),
    );
    if (tooltip == null) return Padding(padding: padding, child: button);
    return Padding(
      padding: padding,
      child: Tooltip(message: tooltip!, child: button),
    );
  }
}
