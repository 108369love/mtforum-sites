import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../pages/user_page.dart';
import 'smart_image.dart';
import 'user_avatar.dart';
import '../navigation/app_routes.dart';

class ThreadCard extends StatelessWidget {
  const ThreadCard({super.key, required this.thread, required this.onTap, this.onDoubleTap});

  final ThreadSummary thread;
  final VoidCallback onTap;

  /// 双击卡片时的动作（首页用来回顶）。
  ///
  /// 给 null 时卡片只有单击，点起来没有延迟；挂上之后单击要等双击判定超时，
  /// 所以调用方只在已经滚离顶部时才传。
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final images = thread.images.where((e) => e.trim().isNotEmpty).toList();

    return Card(
      // 统一主题/回复卡片底色，避免 Material surface tint 造成局部卡片变暗。
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: thread.uid > 0
                        ? () => Navigator.of(context).push(
                              appRoute(
                                builder: (_) => UserPage(uid: thread.uid, name: thread.author),
                              ),
                            )
                        : null,
                    child: UserAvatar(url: thread.avatar, name: thread.author, size: 30),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: thread.uid > 0
                              ? () => Navigator.of(context).push(
                                    appRoute(
                                      builder: (_) => UserPage(uid: thread.uid, name: thread.author),
                                    ),
                                  )
                              : null,
                          child: Text(
                            thread.author.isEmpty ? 'MT论坛' : thread.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          thread.time,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (thread.boardName.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        thread.boardName,
                        style: TextStyle(fontSize: 10.5, color: scheme.primary, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 11),
              Text(
                thread.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.42),
              ),
              if (thread.excerpt.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  thread.excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, height: 1.55, color: scheme.onSurfaceVariant),
                ),
              ],
              if (images.isNotEmpty) ...[
                const SizedBox(height: 11),
                _ImageStrip(images: images),
              ],
              if (thread.replies > 0 || thread.views > 0) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (thread.replies > 0) ...[
                      Icon(Icons.chat_bubble_outline_rounded, size: 13, color: scheme.outline),
                      const SizedBox(width: 4),
                      Text('${thread.replies}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                      const SizedBox(width: 12),
                    ],
                    if (thread.views > 0) ...[
                      Icon(Icons.visibility_outlined, size: 13, color: scheme.outline),
                      const SizedBox(width: 4),
                      Text('${thread.views}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageStrip extends StatelessWidget {
  const _ImageStrip({required this.images});

  final List<String> images;

  @override
  Widget build(BuildContext context) {
    if (images.length == 1) {
      return AspectRatio(
        aspectRatio: 16 / 8.4,
        child: SmartImage(url: images.first, radius: BorderRadius.circular(12)),
      );
    }
    if (images.length == 2) {
      return SizedBox(
        height: 128,
        child: Row(children: [
          Expanded(child: SmartImage(url: images[0], radius: const BorderRadius.horizontal(left: Radius.circular(12)))),
          const SizedBox(width: 3),
          Expanded(child: SmartImage(url: images[1], radius: const BorderRadius.horizontal(right: Radius.circular(12)))),
        ]),
      );
    }
    return SizedBox(
      height: 132,
      child: Row(children: [
        Expanded(flex: 5, child: SmartImage(url: images[0], radius: const BorderRadius.horizontal(left: Radius.circular(12)))),
        const SizedBox(width: 3),
        Expanded(
          flex: 3,
          child: Column(children: [
            Expanded(child: SmartImage(url: images[1], radius: const BorderRadius.only(topRight: Radius.circular(12)))),
            const SizedBox(height: 3),
            Expanded(child: SmartImage(url: images[2], radius: const BorderRadius.only(bottomRight: Radius.circular(12)))),
          ]),
        ),
      ]),
    );
  }
}
