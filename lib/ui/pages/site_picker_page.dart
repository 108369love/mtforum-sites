import 'package:flutter/material.dart';

import '../../core/sites.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_dialog.dart';

/// 站点选择页。
///
/// 站点是全局选择而不是「打开一个新窗口」：切换后主框架整体换一套界面，
/// 所以这里选完直接返回，由 AppShell 重建。
class SitePickerPage extends StatelessWidget {
  const SitePickerPage({super.key});

  Future<void> _switch(BuildContext context, SiteProfile site) async {
    final messenger = ScaffoldMessenger.of(context);
    await SiteStore.instance.select(site);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已切换到 ${site.name}')));
  }

  Future<void> _switchCustom(BuildContext context) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final raw = await showGlassDialog<String>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('自定义站点'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '填站点根地址即可，不用带具体页面。自定义站点一律用内置浏览器打开。',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '站点地址',
                  hintText: 'https://example.com/',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => SiteProfile.tryCustom(value ?? '') == null ? '这不是一个可用的站点地址' : null,
                onFieldSubmitted: (_) {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.of(context).pop(controller.text);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(controller.text);
              }
            },
            child: const Text('打开'),
          ),
        ],
      ),
    );
    if (raw == null || raw.trim().isEmpty) return;
    final site = SiteProfile.tryCustom(raw);
    if (site == null) return;
    if (!context.mounted) return;
    await _switch(context, site);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: SiteStore.instance,
      builder: (context, _) {
        final current = SiteStore.instance.current;
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: const GlassAppBar(title: Text('站点')),
          body: ListView(
            padding: glassPagePadding(context, top: 16, bottom: 30),
            children: [
              Text(
                '选择要浏览的站点。MT论坛走原生界面，XDA 这类 XenForo 站点走内置浏览器——'
                '站点自己的登录、发帖、附件流程都能用，只是界面由站点提供。',
                style: TextStyle(fontSize: 12, height: 1.6, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _sectionTitle(context, '内置站点'),
              const SizedBox(height: 8),
              _siteGroup(
                context,
                current,
                children: [
                  for (final site in SiteProfile.builtin) _siteTile(context, current, site),
                ],
              ),
              const SizedBox(height: 16),
              _sectionTitle(context, '自定义站点'),
              const SizedBox(height: 8),
              _siteGroup(
                context,
                current,
                children: [
                  ListTile(
                    leading: Icon(
                      current.id == SiteProfile.customId ? Icons.language_rounded : Icons.add_link_rounded,
                      color: current.id == SiteProfile.customId ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    title: Text(
                      current.id == SiteProfile.customId ? current.name : '添加站点',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      current.id == SiteProfile.customId ? current.base : '填一个 XenForo / Discuz 站点的根地址',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Icon(
                      current.id == SiteProfile.customId ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                      color: current.id == SiteProfile.customId ? scheme.primary : scheme.outline,
                    ),
                    onTap: () => _switchCustom(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                '原生界面只在 Discuz 站点可用；内置浏览器里的站点不解析页面结构，'
                '站点改版也不会影响它能不能打开。',
                style: TextStyle(fontSize: 11, height: 1.6, color: scheme.outline),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _siteGroup(BuildContext context, SiteProfile current, {required List<Widget> children}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Material(
        // 水波纹要画在最近的 Material 上，垫一层透明的，和「我的」页同一套做法。
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.45)),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _siteTile(BuildContext context, SiteProfile current, SiteProfile site) {
    final scheme = Theme.of(context).colorScheme;
    final selected = site.id == current.id;
    return ListTile(
      leading: Icon(
        site.isNative ? Icons.forum_rounded : Icons.public_rounded,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(
        site.name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(site.tagline, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Icon(
        selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
        color: selected ? scheme.primary : scheme.outline,
      ),
      onTap: selected ? null : () => _switch(context, site),
    );
  }
}
