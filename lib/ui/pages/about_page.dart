import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../widgets/glass_app_bar.dart';

/// 关于本应用。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String _site = 'https://bbs.binmt.cc';
  static const String _manager = 'https://binmt.cc';

  /// 本项目仓库：装的是什么版本，都能顺着这一行找到源码。
  static const String _repo = 'https://github.com/Aioprh/mtforum-app';

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('关于')),
      body: ListView(
        padding: glassPagePadding(context, top: 16, bottom: 30),
        children: [
          Center(
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.primary.withValues(alpha: 0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: scheme.primary.withValues(alpha: 0.3), blurRadius: 22, offset: const Offset(0, 8)),
                ],
              ),
              child: const Icon(Icons.forum_rounded, color: Colors.white, size: 42),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            AppConfig.appName,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3),
          ),
          const SizedBox(height: 5),
          Text(
            '版本 ${AppConfig.versionLabel} · 原生客户端',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('应用说明', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  '本应用是 MT论坛（bbs.binmt.cc）的第三方原生客户端，'
                  '基于论坛移动端页面进行解析与本地渲染，提供更顺滑的浏览、发帖、回复与收藏体验。'
                  '应用不存储任何账号密码，仅在本机保留登录 Cookie。',
                  style: TextStyle(fontSize: 12.5, height: 1.75, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 用 Material 铺底色：ListTile 的水波纹画在最近的 Material 上，
          // 外面套一层带背景色的 Container 会把水波纹挡掉，点下去毫无反馈。
          Material(
            color: scheme.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.public_rounded),
                  title: const Text('MT论坛'),
                  subtitle: Text(AppConfig.host),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 17),
                  onTap: () => _open(_site),
                ),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.45)),
                ListTile(
                  leading: const Icon(Icons.memory_rounded),
                  title: const Text('MT管理器'),
                  subtitle: const Text('binmt.cc'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 17),
                  onTap: () => _open(_manager),
                ),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.45)),
                ListTile(
                  leading: const Icon(Icons.code_rounded),
                  title: const Text('开源地址'),
                  subtitle: const Text('github.com/Aioprh/mtforum-app'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 17),
                  onTap: () => _open(_repo),
                ),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.45)),
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('复制论坛链接'),
                  trailing: const Icon(Icons.copy_rounded, size: 17),
                  onTap: () async {
                    await Clipboard.setData(const ClipboardData(text: _site));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制')));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            '内容版权归 MT论坛及原作者所有',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
