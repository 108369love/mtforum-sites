import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_controls.dart';
import '../widgets/state_views.dart';

/// 隐私筛选（`home.php?mod=spacecp&ac=privacy&op=base`）。
///
/// 只影响「谁能看我的主页 / 广播 / 动态」，和资料设置里逐字段的可见范围
/// 是两套开关：那边管单个字段，这边管整个页面的门。
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  /// 公开 / 好友可见 / 保密 / 仅注册用户可见。
  static const List<(String, String)> _options = [
    ('0', '公开'),
    ('1', '好友可见'),
    ('2', '保密'),
    ('3', '仅注册用户可见'),
  ];

  PrivacySettings? _data;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AppState.instance.repo.fetchPrivacySettings();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is SiteException ? e.message : '$e';
      });
    }
  }

  String _label(String value) =>
      _options.firstWhere((o) => o.$1 == value, orElse: () => _options.first).$2;

  Future<void> _pick(String title, String current, ValueChanged<String> onPicked) async {
    final picked = await showGlassOptionSheet<String>(
      context,
      title: title,
      options: _options,
      selected: current,
    );
    if (!mounted || picked == null) return;
    setState(() => onPicked(picked));
  }

  Future<void> _save() async {
    final data = _data;
    if (data == null || _saving) return;
    setState(() => _saving = true);
    try {
      final message = await AppState.instance.repo.savePrivacySettings(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e is SiteException ? e.message : '$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = _data;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('隐私筛选')),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : ListView(
                    padding: glassPagePadding(context, top: 10, bottom: 34),
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GlassSelectRow(
                              label: '个人主页',
                              leading: Icons.person_outline_rounded,
                              value: _label(data!.home),
                              onTap: () => _pick('个人主页', data.home,
                                  (v) => _data = _data!.copyWith(home: v)),
                            ),
                            const SizedBox(height: 16),
                            GlassSelectRow(
                              label: '广播',
                              leading: Icons.campaign_outlined,
                              value: _label(data.wall),
                              onTap: () => _pick('广播', data.wall,
                                  (v) => _data = _data!.copyWith(wall: v)),
                            ),
                            const SizedBox(height: 16),
                            GlassSelectRow(
                              label: '空间动态',
                              leading: Icons.timeline_rounded,
                              value: _label(data.friend),
                              onTap: () => _pick('空间动态', data.friend,
                                  (v) => _data = _data!.copyWith(friend: v)),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
                        child: Text(
                          '这里只控制整页的可见范围；单个字段（QQ、手机、生日等）的可见性在「资料设置」里各自设置。',
                          style: TextStyle(fontSize: 11.5, height: 1.5, color: scheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('保存'),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
