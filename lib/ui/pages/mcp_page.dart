import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../mcp/keep_alive.dart';
import '../../mcp/mcp_server.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_controls.dart';
import '../widgets/glass_dialog.dart';

/// MCP 服务控制台：开关、地址、token、客户端配置与调用日志。
class McpPage extends StatefulWidget {
  const McpPage({super.key});

  @override
  State<McpPage> createState() => _McpPageState();
}

class _McpPageState extends State<McpPage> {
  /// 是否已加入电池优化白名单，null 表示还没问过系统。
  bool? _batteryExempt;

  @override
  void initState() {
    super.initState();
    unawaited(McpServer.instance.load());
    unawaited(_loadNativeFlags());
  }

  Future<void> _loadNativeFlags() async {
    if (!McpKeepAlive.supported) return;
    final exempt = await McpKeepAlive.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() => _batteryExempt = exempt);
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast('$label 已复制');
  }

  Future<void> _editPort(McpServer server) async {
    final controller = TextEditingController(text: '${server.port}');
    final value = await showGlassDialog<int>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('服务端口'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              hintText: '1024 - 65535',
            ),
            const SizedBox(height: 8),
            Text(
              '换端口后需要重新同步客户端配置',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              Navigator.of(context).pop(parsed);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    if (value < 1024 || value > 65535) {
      _toast('端口需在 1024 - 65535 之间');
      return;
    }
    await server.setPort(value);
  }

  String _config(McpServer server) {
    final url = server.urls.isEmpty ? '' : server.urls.last;
    final args = <String>['-y', 'mcp-remote', url];
    // 关掉令牌校验后不必再带请求头，配置越短越不容易填错。
    if (server.requireToken) {
      args.addAll(<String>['--header', 'Authorization: Bearer ${server.token}']);
    }
    final config = <String, Object?>{
      'mcpServers': <String, Object?>{
        'mtforum': <String, Object?>{
          'command': 'npx',
          'args': args,
        },
      },
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('MCP 服务')),
      body: ListenableBuilder(
        listenable: McpServer.instance,
        builder: (context, _) {
          final server = McpServer.instance;
          return ListView(
            padding: glassPagePadding(context, top: 12, bottom: 32),
            children: [
              _statusCard(context, server, scheme),
              const SizedBox(height: 12),
              _keepAliveCard(server, scheme),
              const SizedBox(height: 12),
              _section('连接地址', [
                for (final url in server.urls)
                  _copyRow(
                    context,
                    icon: Icons.link_rounded,
                    title: url,
                    trailing: '复制',
                    onTap: () => _copy(url, '地址'),
                    scheme: scheme,
                  ),
                if (server.urls.length <= 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      server.allowLan
                          ? '没读到局域网地址，确认手机已连 Wi-Fi'
                          : '已关闭局域网访问，只有本机进程能连',
                      style: TextStyle(fontSize: 11.5, color: scheme.outline),
                    ),
                  ),
              ], scheme),
              const SizedBox(height: 12),
              _section(server.requireToken ? '访问令牌' : '访问令牌（未启用）', [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        server.token,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.5,
                          fontFamily: 'monospace',
                          color: server.requireToken ? scheme.onSurfaceVariant : scheme.outline,
                          decoration: server.requireToken ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _copy(server.token, '令牌'),
                      child: const Text('复制'),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      final confirmed = await showGlassDialog<bool>(
                        context: context,
                        builder: (context) => GlassDialog(
                          title: const Text('重置令牌？'),
                          content: const Text('重置后旧的客户端配置会立刻失效，需要重新复制新令牌。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('重置'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      await server.regenerateToken();
                      _toast('令牌已重置');
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('重置令牌'),
                  ),
                ),
              ], scheme),
              const SizedBox(height: 12),
              _section('权限', [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: server.requireToken,
                  onChanged: (value) => server.setRequireToken(value),
                  title: const Text('要求令牌验证', style: TextStyle(fontSize: 13.5)),
                  subtitle: Text(
                    server.requireToken
                        ? '客户端需带 Authorization: Bearer 令牌'
                        : '已关闭：同一网络下任何人都能调用，包括发帖与回复',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: server.requireToken ? scheme.outline : scheme.error,
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: server.allowLan,
                  onChanged: (value) => server.setAllowLan(value),
                  title: const Text('允许局域网访问', style: TextStyle(fontSize: 13.5)),
                  subtitle: Text(
                    '关闭后只监听 127.0.0.1，电脑就连不上了',
                    style: TextStyle(fontSize: 11.5, color: scheme.outline),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: server.allowWrite,
                  onChanged: (value) => server.setAllowWrite(value),
                  title: const Text('允许写入操作', style: TextStyle(fontSize: 13.5)),
                  subtitle: Text(
                    '关闭后 AI 只能读帖、搜索，不能发帖、回复、签到',
                    style: TextStyle(fontSize: 11.5, color: scheme.outline),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _editPort(server),
                  title: const Text('端口', style: TextStyle(fontSize: 13.5)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${server.port}', style: TextStyle(fontSize: 13, color: scheme.primary)),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline),
                    ],
                  ),
                ),
              ], scheme),
              const SizedBox(height: 12),
              _configCard(context, server, scheme),
              const SizedBox(height: 12),
              _logCard(context, server, scheme),
            ],
          );
        },
      ),
    );
  }

  Widget _statusCard(BuildContext context, McpServer server, ColorScheme scheme) {
    final running = server.running;
    final color = running ? const Color(0xFF2E9E5B) : scheme.outline;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: running ? color.withValues(alpha: 0.08) : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: running ? 0.3 : 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  running ? '服务运行中' : '服务已停止',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: running ? color : scheme.onSurface),
                ),
                const SizedBox(height: 3),
                Text(
                  server.lastError ??
                      (running
                          ? '已处理 ${server.calls} 次调用'
                          : '开启后同一 Wi-Fi 下的 AI 客户端即可连接'),
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: running ? color.withValues(alpha: 0.9) : scheme.outline,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: server.enabled,
            onChanged: (value) async {
              await server.setEnabled(value);
              if (server.lastError != null) _toast(server.lastError!);
            },
          ),
        ],
      ),
    );
  }

  /// 「后台运行」：保活开关 + 电池优化白名单。
  ///
  /// 保活是靠一个前台服务把进程按住，通知栏会常驻一条低优先级通知；
  /// 不开的话切后台没多久系统就可能把进程回收，电脑那头的连接直接断。
  Widget _keepAliveCard(McpServer server, ColorScheme scheme) {
    final on = server.keepAlive;
    final active = server.keepAliveActive;
    return _section('后台运行', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: on,
        onChanged: (value) async {
          await server.setKeepAlive(value);
          if (!value) return;
          if (!server.running) {
            _toast('服务未开启，保活会在开启服务后生效');
            return;
          }
          if (!await McpKeepAlive.hasNotificationPermission()) {
            final granted = await McpKeepAlive.requestNotificationPermission();
            if (!granted) _toast('没给通知权限：服务照常运行，但通知栏看不到');
          }
        },
        title: const Text('后台保活', style: TextStyle(fontSize: 13.5)),
        subtitle: Text(
          !on
              ? '开启后切到后台、锁屏也能被 AI 客户端连上'
              : active
                  ? '前台服务运行中，通知栏常驻一条低优先级通知'
                  : '已记录，开启服务后自动生效',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.45,
            color: on && active ? const Color(0xFF2E9E5B) : scheme.outline,
          ),
        ),
      ),
      if (McpKeepAlive.supported)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('忽略电池优化', style: TextStyle(fontSize: 13.5)),
          subtitle: Text(
            _batteryExempt == true
                ? '已加入白名单，后台更稳'
                : '部分机型锁屏后会掐断网络，建议加入白名单',
            style: TextStyle(fontSize: 11.5, color: scheme.outline),
          ),
          trailing: Text(
            _batteryExempt == true ? '已开启' : '去设置',
            style: TextStyle(fontSize: 12, color: scheme.primary),
          ),
          onTap: () async {
            await McpKeepAlive.requestIgnoreBatteryOptimizations();
            final exempt = await McpKeepAlive.isIgnoringBatteryOptimizations();
            if (!mounted) return;
            setState(() => _batteryExempt = exempt);
            _toast(exempt ? '已在电池优化白名单里' : '还没加入白名单');
          },
        ),
    ], scheme);
  }

  Widget _section(String title, List<Widget> children, ColorScheme scheme) {
    // 同上：底色交给 Material，SwitchListTile 的水波纹才不会被挡。
    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _copyRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String trailing,
    required VoidCallback onTap,
    required ColorScheme scheme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 15, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Text(trailing, style: TextStyle(fontSize: 11.5, color: scheme.primary)),
          ],
        ),
      ),
    );
  }

  Widget _configCard(BuildContext context, McpServer server, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('客户端配置', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              TextButton(
                onPressed: () => _copy(_config(server), '配置'),
                child: const Text('复制'),
              ),
            ],
          ),
          Text(
            server.requireToken
                ? 'Claude Desktop / Cursor 等支持 stdio 的客户端，把下面这段放进 mcpServers；'
                    '直接支持 HTTP 的客户端（Cherry Studio 等）选「Streamable HTTP」，'
                    '地址填上面的 URL，请求头加 Authorization: Bearer 令牌。'
                : '令牌校验已关闭，下面的配置不用带请求头；'
                    '直接支持 HTTP 的客户端填上面的 URL 即可直接连。',
            style: TextStyle(fontSize: 11.5, height: 1.6, color: scheme.outline),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _config(server),
              style: TextStyle(
                fontSize: 10.5,
                height: 1.55,
                fontFamily: 'monospace',
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '提示：把 App 留在前台，切到后台后系统可能挂起网络服务。',
            style: TextStyle(fontSize: 11, height: 1.5, color: scheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _logCard(BuildContext context, McpServer server, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '调用日志（${server.calls}）',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              if (server.logs.isNotEmpty)
                TextButton(
                  onPressed: server.clearLogs,
                  child: const Text('清空'),
                ),
            ],
          ),
          if (server.logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '还没有调用记录',
                style: TextStyle(fontSize: 11.5, color: scheme.outline),
              ),
            )
          else
            for (final entry in server.logs.take(30))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 54,
                      child: Text(
                        _clock(entry.at),
                        style: TextStyle(fontSize: 10.5, color: scheme.outline),
                      ),
                    ),
                    Icon(
                      entry.ok ? Icons.check_circle_rounded : Icons.error_rounded,
                      size: 13,
                      color: entry.ok ? const Color(0xFF2E9E5B) : scheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.title} · ${entry.ms}ms',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                          if (entry.detail.isNotEmpty)
                            Text(
                              entry.detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10.5, height: 1.4, color: scheme.outline),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  String _clock(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }
}
