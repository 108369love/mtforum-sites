import 'dart:ui';

import 'package:flutter/material.dart';

import '../../state/app_state.dart';

/// 发帖入口的液态玻璃悬浮按钮。
///
/// 透明度和背景模糊度由「我的 → 发帖按钮液态玻璃」调节，实时读取 [AppState]，
/// 因此设置页改动后无需重启即可生效。
class GlassComposeButton extends StatelessWidget {
  const GlassComposeButton({
    super.key,
    required this.onPressed,
    this.opacity,
    this.blur,
    this.compact = false,
  });

  final VoidCallback onPressed;

  /// 指定透明度；为空时取全局设置。用于设置页的实时预览。
  final double? opacity;

  /// 指定模糊度；为空时取全局设置。用于设置页的实时预览。
  final double? blur;

  /// 预览模式下不显示文字，只保留图标。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final alpha = (opacity ?? AppState.instance.composeGlassOpacity).clamp(0.05, 0.75).toDouble();
    final sigma = (blur ?? AppState.instance.composeGlassBlur).clamp(0.0, 40.0).toDouble();

    // 与底栏液态玻璃保持同一套色板，避免两处观感割裂。
    final topColor = isDark ? const Color(0xFF303945) : Colors.white;
    final bottomColor = isDark ? const Color(0xFF171D26) : const Color(0xFFF1F5FA);

    return Semantics(
      button: true,
      label: '发帖',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              child: Container(
                padding: compact
                    ? const EdgeInsets.all(12)
                    : const EdgeInsets.fromLTRB(20, 13, 22, 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      topColor.withValues(alpha: alpha),
                      bottomColor.withValues(alpha: alpha * 0.72),
                    ],
                  ),
                  border: Border.all(
                    color: (isDark ? Colors.white : scheme.outlineVariant)
                        .withValues(alpha: isDark ? 0.20 : 0.34),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_rounded, size: 19, color: scheme.primary),
                    if (!compact) ...[
                      const SizedBox(width: 8),
                      Text(
                        '发帖',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
