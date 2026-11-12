import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_controls.dart';
import '../widgets/state_views.dart';
import '../widgets/user_avatar.dart';

/// 我的等级：用户组、升级进度和这一组能做什么。
///
/// 原站在 `home.php?mod=spacecp&ac=usergroup`，移动模板把等级头和权限表放在
/// 同一页。这里照搬信息层级，但把「有权/无权」的字体图标换成了明确的勾叉。
class UserGroupPage extends StatefulWidget {
  const UserGroupPage({super.key});

  @override
  State<UserGroupPage> createState() => _UserGroupPageState();
}

class _UserGroupPageState extends State<UserGroupPage> {
  UserGroupInfo? _info;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AppState.instance.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = '登录后才能查看等级';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await AppState.instance.repo.fetchUserGroupInfo();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } on SiteException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '等级信息加载失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('我的等级')),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    edgeOffset: glassTopInset(context),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: glassPagePadding(context, top: 10, bottom: 34),
                      children: [
                        _header(scheme, _info!),
                        const SizedBox(height: 18),
                        _permissionList(scheme, _info!),
                        const SizedBox(height: 16),
                        Text(
                          '权限由站点按用户组配置，升级后自动生效。',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11.5, color: scheme.outline),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _header(ColorScheme scheme, UserGroupInfo info) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: isDark ? 0.24 : 0.16),
            scheme.primary.withValues(alpha: isDark ? 0.08 : 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(url: info.avatar, name: info.name, size: 54),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.name.isEmpty ? '我的等级' : info.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (info.level.isNotEmpty) _tag(scheme, info.level, filled: true),
                        if (info.level.isNotEmpty && info.nextLevel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward_rounded, size: 13, color: scheme.outline),
                          ),
                        if (info.nextLevel.isNotEmpty) _tag(scheme, info.nextLevel, filled: false),
                      ],
                    ),
                  ],
                ),
              ),
              if (info.credits.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      info.credits,
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: scheme.primary),
                    ),
                    Text('积分', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: info.progress,
              minHeight: 8,
              backgroundColor: scheme.primary.withValues(alpha: 0.14),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            info.hasNext
                ? '还需要 ${info.remaining} 积分升级到 ${info.nextName}'
                : '已经是当前分组的最高等级',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _tag(ColorScheme scheme, String text, {required bool filled}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: filled ? scheme.primary.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: filled ? Colors.transparent : scheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: filled ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _permissionList(ColorScheme scheme, UserGroupInfo info) {
    if (info.permissions.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(18),
        child: Text('站点没有返回权限明细', style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '我的论坛权限',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.3,
            ),
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < info.permissions.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                _permissionRow(scheme, info.permissions[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _permissionRow(ColorScheme scheme, GroupPermission permission) {
    final allowed = permission.allowed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              permission.name,
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
          const SizedBox(width: 12),
          if (allowed == null)
            Text(
              permission.value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            )
          else
            Icon(
              allowed ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
              size: 18,
              color: allowed ? scheme.primary : scheme.outlineVariant,
            ),
        ],
      ),
    );
  }
}
