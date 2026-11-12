import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../state/app_state.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_controls.dart';

/// 登录 MT 论坛账号。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const List<(int, String)> _questions = [
    (0, '无安全提问'),
    (1, '母亲的名字'),
    (2, '爷爷的名字'),
    (3, '父亲出生的城市'),
    (4, '您其中一位老师的名字'),
    (5, '您个人计算机的型号'),
    (6, '您最喜欢的餐馆名称'),
    (7, '驾驶执照最后四位数字'),
  ];

  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _answer = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  int _questionId = 0;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _answer.dispose();
    super.dispose();
  }

  Future<void> _pickQuestion() async {
    final picked = await showGlassOptionSheet<int>(
      context,
      title: '安全提问',
      options: _questions,
      selected: _questionId,
    );
    if (!mounted || picked == null || picked == _questionId) return;
    setState(() => _questionId = picked);
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppState.instance.login(
        username,
        password,
        questionId: _questionId,
        answer: _answer.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is SiteException ? e.message : '登录失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final question = _questions.firstWhere((e) => e.$1 == _questionId).$2;

    return Scaffold(
      extendBodyBehindAppBar: true,
      // 页面本身有一个 25sp 的大标题，顶栏再写一遍「登录」就重复了。
      appBar: const GlassAppBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(22, glassTopInset(context) + 14, 22, 30),
          children: [
            // ListView 会给子项一个「铺满可用宽度」的紧约束，直接放 58 宽的
            // 方块会被拉成一整条渐变横幅，得靠 Align 把紧约束松开。
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.primary.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.forum_rounded, color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '登录 MT论坛',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.4),
            ),
            const SizedBox(height: 6),
            Text(
              '使用论坛账号登录后即可发帖、回复与收藏',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 26),
            GlassField(
              controller: _username,
              label: '用户名',
              hintText: '请输入论坛用户名',
              leading: Icons.person_outline_rounded,
              textInputAction: TextInputAction.next,
              autofocus: true,
            ),
            const SizedBox(height: 14),
            GlassField(
              controller: _password,
              label: '密码',
              hintText: '请输入登录密码',
              leading: Icons.lock_outline_rounded,
              textInputAction: TextInputAction.done,
              obscureText: _obscure,
              onSubmitted: (_) => _submit(),
              trailing: _ObscureToggle(
                obscure: _obscure,
                onTap: () => setState(() => _obscure = !_obscure),
              ),
            ),
            const SizedBox(height: 14),
            GlassSelectRow(
              label: '安全提问',
              value: question,
              leading: Icons.help_outline_rounded,
              onTap: _pickQuestion,
            ),
            if (_questionId != 0) ...[
              const SizedBox(height: 14),
              GlassField(
                controller: _answer,
                label: '安全提问答案',
                hintText: '请输入答案',
                leading: Icons.verified_user_outlined,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(fontSize: 12.5, height: 1.5, color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 26),
            FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Text('登录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 16),
            Text(
              '登录信息仅用于向 bbs.binmt.cc 提交，本应用不会上传到其他服务器。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, height: 1.6, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// 密码可见性切换。做成两个图标叠着淡入淡出，比换图标少一点跳动。
class _ObscureToggle extends StatelessWidget {
  const _ObscureToggle({required this.obscure, required this.onTap});

  final bool obscure;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 19,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}
