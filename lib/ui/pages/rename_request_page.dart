import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_controls.dart';
import '../widgets/glass_dialog.dart';
import '../widgets/state_views.dart';

/// 改名申请。
///
/// 站点把改名做成了一个插件（`nimba_rename`），入口只在 PC 顶栏的
/// 「改名申请」里，手机模板没有。流程是：填新用户名 + 理由 → 扣金币 →
/// 管理员人工改。所以这个页面不承诺「立即改名」，只把申请送出去。
class RenameRequestPage extends StatefulWidget {
  const RenameRequestPage({super.key});

  /// 用户名规则按站点来：2–15 个字符，不能带空格和几个会打断表单的符号。
  static String? validateName(String value, String current) {
    final name = value.trim();
    if (name.isEmpty) return '请填写新用户名';
    if (current.isNotEmpty && name == current) return '新用户名和当前用户名一样';
    if (name.runes.length < 2) return '用户名至少 2 个字符';
    if (name.runes.length > 15) return '用户名最多 15 个字符';
    if (RegExp(r'\s').hasMatch(name)) return '用户名不能包含空格';
    if (RegExp(r'''[<>"'&%\\/]''').hasMatch(name)) return '用户名不能包含 < > " \' & % / \\';
    return null;
  }

  static String? validateReason(String value) {
    final reason = value.trim();
    if (reason.isEmpty) return '请填写改名理由';
    if (reason.runes.length > 20) return '改名理由不超过 20 字';
    return null;
  }

  @override
  State<RenameRequestPage> createState() => _RenameRequestPageState();
}

class _RenameRequestPageState extends State<RenameRequestPage> {
  final _name = TextEditingController();
  final _reason = TextEditingController();

  RenameInfo? _info;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!AppState.instance.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = '登录后才能申请改名';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await AppState.instance.repo.fetchRenameInfo();
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
        _error = '改名申请页面加载失败，请稍后重试';
      });
    }
  }

  Future<void> _submit() async {
    final info = _info;
    if (info == null || _submitting) return;

    final current = AppState.instance.profile?.username ?? '';
    final nameError = RenameRequestPage.validateName(_name.text, current);
    if (nameError != null) {
      _toast(nameError);
      return;
    }
    final reasonError = RenameRequestPage.validateReason(_reason.text);
    if (reasonError != null) {
      _toast(reasonError);
      return;
    }

    final name = _name.text.trim();
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('确认提交改名申请'),
        content: Text(
          '新用户名：$name\n\n提交后扣除 ${info.fee} 金币，由管理员人工审核改名。'
          '审核通过前用户名不会变，请不要重复提交。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('再想想')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('提交')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final message = await AppState.instance.repo.requestRename(
        newName: name,
        reason: _reason.text.trim(),
      );
      // 金币已经扣了，顺手把资料里的数目刷新一下。
      AppState.instance.refreshProfile(silent: true);
      if (!mounted) return;
      _toast(message);
      Navigator.of(context).pop(true);
    } on SiteException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast('提交失败，请稍后重试');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('改名申请')),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : ListView(
                    padding: glassPagePadding(context, top: 10, bottom: 34),
                    children: [
                      _summaryCard(scheme),
                      const SizedBox(height: 16),
                      GlassField(
                        controller: _name,
                        label: '新用户名',
                        hintText: '2–15 个字符，不能带空格',
                        leading: Icons.alternate_email_rounded,
                        maxLength: 15,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),
                      GlassField(
                        controller: _reason,
                        label: '改名理由',
                        hintText: '写清楚一点，乱填审核不会通过',
                        leading: Icons.edit_note_rounded,
                        minLines: 3,
                        maxLines: 4,
                        maxLength: 20,
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('提交申请'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '改名由站长/管理员人工处理，通常需要一两天；'
                        '审核结果出来后用户名才会变化。',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, height: 1.5, color: scheme.outline),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _summaryCard(ColorScheme scheme) {
    final info = _info!;
    final profile = AppState.instance.profile;
    final current = profile?.username ?? '—';
    final coins = profile?.credits ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.badge_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  current,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
              ),
              if (coins.isNotEmpty)
                Text(
                  '$coins 金币',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '每次申请扣除 ${info.fee} 金币，提交后进入人工审核队列。'
            '新用户名被别人占用、或理由写得太随意，都可能不通过。',
            style: TextStyle(fontSize: 12.5, height: 1.55, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
