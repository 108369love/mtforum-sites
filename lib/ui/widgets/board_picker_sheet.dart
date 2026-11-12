import 'package:flutter/material.dart';

import '../../data/models.dart';
import 'glass_controls.dart';
import 'thread_glass.dart';

/// 版块选择浮层：按分区列出全部版块，选中即回传 fid。
///
/// 搜索页和发帖页共用。原来的下拉菜单一展开就是一张铺满屏幕的灰板，
/// 十几个版块挤成「分区 / 版块」长字符串，既看不清也选不准。
class BoardPickerSheet extends StatelessWidget {
  const BoardPickerSheet({
    super.key,
    required this.categories,
    required this.selected,
    this.showAll = true,
  });

  final List<ForumCategory> categories;
  final int selected;

  /// 是否给出「全部版块」这一项。搜索可以不限版块，发帖必须落到具体版块。
  final bool showAll;

  /// 弹出选择浮层，返回选中的 fid；用户直接关掉返回 null。
  static Future<int?> show(
    BuildContext context, {
    required List<ForumCategory> categories,
    required int selected,
    bool showAll = true,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.26),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BoardPickerSheet(
        categories: categories,
        selected: selected,
        showAll: showAll,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.68;
    final total = categories.fold<int>(0, (sum, e) => sum + e.boards.length);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: GlassBackdrop(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        opacityScale: 1.06,
        showShadow: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 9),
            Container(
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 2),
              child: Row(
                children: [
                  const Text('选择版块', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Text('$total 个', style: TextStyle(fontSize: 11.5, color: scheme.outline)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            Flexible(
              // shrinkWrap + loose：版块少的时候浮层只有内容那么高，
              // 多了才顶到 68% 的上限，不会留一大块空玻璃。
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 18),
                children: [
                  if (showAll) ...[
                    _AllBoardsTile(
                      selected: selected == 0,
                      onTap: () => Navigator.of(context).pop(0),
                    ),
                    const SizedBox(height: 4),
                  ],
                  for (final category in categories) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 9),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 12,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            category.name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${category.boards.length}',
                            style: TextStyle(fontSize: 10.5, color: scheme.outline),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final board in category.boards)
                          GlassPill(
                            label: board.name,
                            selected: board.fid == selected,
                            fontSize: 13,
                            padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                            onTap: () => Navigator.of(context).pop(board.fid),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllBoardsTile extends StatelessWidget {
  const _AllBoardsTile({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected ? scheme.primary : scheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected
              ? scheme.primary.withValues(alpha: isDark ? 0.22 : 0.13)
              : Colors.white.withValues(alpha: isDark ? 0.09 : 0.44),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: isDark ? 0.45 : 0.34)
                : ThreadGlass.borderColor(context),
            width: 0.9,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.apps_rounded, size: 18, color: fg),
            const SizedBox(width: 10),
            Text('全部版块', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: fg)),
            const Spacer(),
            if (selected) Icon(Icons.check_rounded, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
