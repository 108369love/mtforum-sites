import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/userscripts.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_dialog.dart';

/// 用户脚本（油猴脚本）管理页。
///
/// 只做三件事：装进来、开关、删掉。脚本在页面加载完成后注入到内置浏览器里，
/// `GM_xmlhttpRequest` 由内置垫片转给原生 HTTP 发出（没有 CORS 限制）。
class UserScriptsPage extends StatelessWidget {
  const UserScriptsPage({super.key});

  Future<void> _install(BuildContext context, String code) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await UserScriptStore.instance.import(code);
    if (!context.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _importFromFile(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      if (!context.mounted) return;
      await _install(context, text);
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }

  Future<void> _importFromClipboard(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!context.mounted) return;
    if (text.isEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('剪贴板里没有文本')));
      return;
    }
    await _install(context, text);
  }

  Future<void> _remove(BuildContext context, UserScript script) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('删除脚本'),
        content: Text('确定删除「${script.name}」吗？删掉之后要重新导入。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    await UserScriptStore.instance.remove(script.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: UserScriptStore.instance,
      builder: (context, _) {
        final scripts = UserScriptStore.instance.scripts;
        final anyEnabled = UserScriptStore.instance.anyEnabled;
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GlassAppBar(
            title: const Text('用户脚本'),
            actions: [
              PopupMenuButton<String>(
                tooltip: '导入脚本',
                icon: const Icon(Icons.add_rounded),
                onSelected: (value) {
                  if (value == 'file') _importFromFile(context);
                  if (value == 'clipboard') _importFromClipboard(context);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'file', child: Text('从文件导入 .user.js')),
                  PopupMenuItem(value: 'clipboard', child: Text('从剪贴板导入')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: glassPagePadding(context, top: 16, bottom: 30),
            children: [
              Text(
                '支持油猴脚本的 @name / @match，页面加载完成后注入。'
                '跨域请求通过 GM_xmlhttpRequest 转发到原生 HTTP，不受 CORS 限制。'
                '脚本只在本机保存，不上传。',
                style: TextStyle(fontSize: 12, height: 1.6, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              if (scripts.isNotEmpty) ...[
                _group(
                  context,
                  children: [
                    SwitchListTile(
                      value: anyEnabled,
                      title: const Text('全部启用', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: const Text('一键停用所有脚本，单个开关仍然有效'),
                      onChanged: (value) => UserScriptStore.instance.setAllEnabled(value),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _group(
                  context,
                  children: [
                    for (final script in scripts)
                      ListTile(
                        leading: Icon(Icons.code_rounded, color: scheme.primary),
                        title: Text(script.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          script.matches.join('  '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: script.enabled,
                              onChanged: (value) => UserScriptStore.instance.setEnabled(script.id, value),
                            ),
                            IconButton(
                              tooltip: '删除',
                              onPressed: () => _remove(context, script),
                              icon: Icon(Icons.delete_outline_rounded, size: 20, color: scheme.error),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.extension_outlined, size: 42, color: scheme.outline),
                      const SizedBox(height: 10),
                      const Text('还没有安装脚本', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                        '右上角 + 从文件或剪贴板导入 .user.js',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Text(
                '提示：装好后回到浏览器刷新页面即生效；停用某个脚本后同样需要刷新。'
                '脚本出错不会影响页面本身。',
                style: TextStyle(fontSize: 11, height: 1.6, color: scheme.outline),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _group(BuildContext context, {required List<Widget> children}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Material(
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
}
