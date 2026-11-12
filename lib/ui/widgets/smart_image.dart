import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';

/// 带站点 Referer / Cookie 的网络图片，未加载完成时显示柔和占位。
class SmartImage extends StatelessWidget {
  const SmartImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = BorderRadius.zero,
    this.cacheWidth,
    this.placeholderHeight,
    this.filterQuality = FilterQuality.low,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius radius;
  final int? cacheWidth;

  /// 加载中/加载失败时占位块的高度。为空时沿用父级约束（列表封面等场景）。
  /// 正文里的长图不需要在加载时先占满一屏，给个矮的占位即可。
  final double? placeholderHeight;

  /// 缩放采样质量。默认 low：正文动辄几十张上千像素的截图，
  /// medium（默认值）每帧插值更贵，滚动时掉帧明显，肉眼几乎看不出差别。
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: width,
      height: height ?? placeholderHeight,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: scheme.onSurfaceVariant.withValues(alpha: 0.5), size: 22),
    );

    if (url.trim().isEmpty) {
      return ClipRRect(borderRadius: radius, child: placeholder);
    }

    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.scheme == 'file') {
      return ClipRRect(
        borderRadius: radius,
        child: Image.file(
          File(parsed.toFilePath()),
          width: width,
          height: height,
          fit: fit,
          filterQuality: filterQuality,
          cacheWidth: cacheWidth,
          errorBuilder: (_, __, ___) => placeholder,
        ),
      );
    }

    final cookie = HttpSession.instance.cookieHeader;
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        filterQuality: filterQuality,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        headers: {
          'Referer': AppConfig.base,
          'User-Agent': AppConfig.userAgent,
          if (cookie.isNotEmpty) 'Cookie': cookie,
        },
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          final total = progress.expectedTotalBytes;
          final value = total == null ? null : progress.cumulativeBytesLoaded / total;
          final box = Stack(
            fit: StackFit.expand,
            children: [
              placeholder,
              if (value != null)
                Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, value: value, color: scheme.primary),
                  ),
                ),
            ],
          );
          // 有明确占位高度时用它，否则沿用约束（旧行为）。
          final limit = placeholderHeight;
          if (limit == null) return box;
          return SizedBox(width: width, height: limit, child: box);
        },
      ),
    );
  }
}
