import 'package:flutter/material.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry, this.compact = false});

  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 28, vertical: compact ? 16 : 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: compact ? 34 : 54, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: scheme.onSurfaceVariant),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新加载'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.text, this.icon = Icons.forum_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 50),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: scheme.outline.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// 骨架屏的形状：帖子卡片、列表行、网格方块。
enum SkeletonKind { card, row, grid }

/// 首屏骨架屏，避免空白等待。
///
/// 之前帖子列表用骨架、其余十几个页面用转圈，慢网下有的页面淡入占位、有的
/// 干等一个圆圈，观感割裂。[SkeletonView] 把三种常见形状收在一起，
/// [FeedSkeleton] 只是它的帖子卡片形态。
class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) =>
      SkeletonView(kind: SkeletonKind.card, count: count, gutter: 16);
}

class SkeletonView extends StatefulWidget {
  const SkeletonView({
    super.key,
    this.kind = SkeletonKind.card,
    this.count,
    this.topInset = 0,
    this.gutter = 14,
  });

  final SkeletonKind kind;
  final int? count;

  /// 玻璃顶栏占掉的高度，骨架从它下面开始，不要压到玻璃上。
  final double topInset;
  final double gutter;

  @override
  State<SkeletonView> createState() => _SkeletonViewState();
}

class _SkeletonViewState extends State<SkeletonView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest.withValues(alpha: 0.45);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = 0.45 + _controller.value * 0.35;
        Widget bar(double width, double height, {double radius = 6}) => Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: base.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(radius),
              ),
            );
        final padding = EdgeInsets.fromLTRB(widget.gutter, widget.topInset + 10, widget.gutter, 24);
        switch (widget.kind) {
          case SkeletonKind.grid:
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // 显式 padding：不写的话网格会继承 MediaQuery 的安全区，
              // 开了 extendBodyBehindAppBar 的页面会凭空多出一整块空白。
              padding: padding,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisExtent: 70,
                mainAxisSpacing: 12,
                crossAxisSpacing: 8,
              ),
              itemCount: widget.count ?? 8,
              itemBuilder: (_, __) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [bar(38, 38, radius: 19), const SizedBox(height: 8), bar(46, 8)],
              ),
            );
          case SkeletonKind.row:
            return ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              padding: padding,
              itemCount: widget.count ?? 8,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, __) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    bar(44, 44, radius: 22),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [bar(96, 12), const SizedBox(height: 8), bar(140, 9)],
                      ),
                    ),
                  ],
                ),
              ),
            );
          case SkeletonKind.card:
            return ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              padding: padding,
              itemCount: widget.count ?? 5,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, __) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        bar(32, 32, radius: 16),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [bar(80, 11), const SizedBox(height: 6), bar(50, 9)],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    bar(double.infinity, 14),
                    const SizedBox(height: 8),
                    bar(double.infinity, 14),
                    const SizedBox(height: 12),
                    bar(210, 10),
                  ],
                ),
              ),
            );
        }
      },
    );
  }
}
