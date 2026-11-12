import 'package:flutter/material.dart';

import '../../state/app_state.dart';

/// 阅读配色：正文里的链接和「回复可见」提示。
///
/// 论坛的帖子经常是几百行的长文，链接和「需要回复才能看」的提示跟正文一个
/// 颜色，划着划着就漏了。颜色对色弱用户尤其不友好，所以这里不只给一套默认
/// 色，还留了 8 个色相分散的预设，让用户自己挑能看清的。
Future<void> showReadPaletteSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _ReadPaletteSheet(),
  );
}

class _ReadPaletteSheet extends StatefulWidget {
  const _ReadPaletteSheet();

  @override
  State<_ReadPaletteSheet> createState() => _ReadPaletteSheetState();
}

class _ReadPaletteSheetState extends State<_ReadPaletteSheet> {
  /// 八个色相拉开的候选；明度都压在白底和 #0D1117 上都还能看清的区间。
  static const List<(String, Color)> _presets = <(String, Color)>[
    ('宝蓝', Color(0xFF2563EB)),
    ('湖蓝', Color(0xFF0891B2)),
    ('松绿', Color(0xFF16A34A)),
    ('琥珀', Color(0xFFEA8C1B)),
    ('朱红', Color(0xFFDC2626)),
    ('品红', Color(0xFFDB2777)),
    ('靛紫', Color(0xFF7C3AED)),
    ('赭黄', Color(0xFFA16207)),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = AppState.instance;
    final link = state.readLinkColorOf(scheme);
    final hint = state.readHintColorOf(scheme);
    final linkIsDefault = state.readLinkColor == null;
    final hintIsDefault = state.readHintColor == null;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('阅读配色', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              '长帖里的链接和「需要回复」提示容易看漏，可以单独换颜色，改完立即生效。',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _preview(scheme, link, hint),
            const SizedBox(height: 20),
            _sectionTitle('链接颜色'),
            const SizedBox(height: 10),
            _swatches(
              current: state.readLinkColor,
              fallback: scheme.primary,
              fallbackLabel: '跟随主题',
              selectedDefault: linkIsDefault,
              onDefault: () => _pick(null, link: true),
              onPick: (color) => _pick(color, link: true),
            ),
            const SizedBox(height: 20),
            _sectionTitle('回复提示颜色'),
            const SizedBox(height: 10),
            _swatches(
              current: state.readHintColor,
              fallback: state.readHintColorOf(scheme),
              fallbackLabel: '默认',
              selectedDefault: hintIsDefault,
              onDefault: () => _pick(null, link: false),
              onPick: (color) => _pick(color, link: false),
            ),
            const SizedBox(height: 18),
            Text(
              '色弱的话建议挑和你常用背景对比最强的那个；链接还带下划线，提示行会加粗。',
              style: TextStyle(fontSize: 11.5, height: 1.5, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(Color? color, {required bool link}) async {
    final state = AppState.instance;
    if (link) {
      await state.setReadLinkColor(color);
    } else {
      await state.setReadHintColor(color);
    }
    if (mounted) setState(() {});
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      );

  /// 改色之前先看效果：一行带链接的正文 + 一行回复可见提示。
  Widget _preview(ColorScheme scheme, Color link, Color hint) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: '下载地址：'),
                TextSpan(
                  text: 'pan.baidu.com/s/1AbCdEf',
                  style: TextStyle(color: link, decoration: TextDecoration.underline),
                ),
              ],
            ),
            style: TextStyle(fontSize: 14, height: 1.7, color: scheme.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            '本帖隐藏的内容需要回复后才能查看',
            style: TextStyle(
              fontSize: 14,
              height: 1.7,
              color: hint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _swatches({
    required Color? current,
    required Color fallback,
    required String fallbackLabel,
    required bool selectedDefault,
    required VoidCallback onDefault,
    required ValueChanged<Color> onPick,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 12,
      children: [
        _Swatch(
          color: fallback,
          label: fallbackLabel,
          selected: selectedDefault,
          onTap: onDefault,
          isFallback: true,
          scheme: scheme,
        ),
        for (final option in _presets)
          _Swatch(
            color: option.$2,
            label: option.$1,
            selected: !selectedDefault && current?.toARGB32() == option.$2.toARGB32(),
            onTap: () => onPick(option.$2),
            scheme: scheme,
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.scheme,
    this.isFallback = false,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  /// 「跟随主题 / 默认」那一格：显示当前生效色，角上带一个小回环图标。
  final bool isFallback;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 66,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: selected ? Border.all(color: scheme.onSurface, width: 3) : null,
                ),
                child: selected
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                    : (isFallback
                        ? Icon(Icons.sync_rounded, color: Colors.white.withValues(alpha: 0.85), size: 18)
                        : null),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: selected ? scheme.onSurface : scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
