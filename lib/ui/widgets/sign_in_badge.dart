import 'package:flutter/material.dart';

/// 用户卡片里的签到状态条。
///
/// 自动签到是静默跑的，没有这个位置，用户既不知道今天签没签，也没法补签。
class SignInBadge extends StatelessWidget {
  const SignInBadge({
    super.key,
    required this.signedIn,
    this.busy = false,
    this.onSignIn,
  });

  final bool signedIn;

  /// 签到请求进行中：转圈，且不响应点击。
  final bool busy;

  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tone = signedIn
        ? (dark ? const Color(0xFF7BD88F) : const Color(0xFF2E7D32))
        : scheme.onSurfaceVariant;
    final tappable = !signedIn && !busy && onSignIn != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: tappable ? onSignIn : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            if (busy)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.8, color: scheme.primary),
              )
            else
              Icon(
                signedIn ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 15,
                color: signedIn ? tone : scheme.outline,
              ),
            const SizedBox(width: 6),
            Text(
              signedIn ? '今日已签到' : '今日未签到',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tone),
            ),
            if (signedIn) ...[
              const SizedBox(width: 6),
              Text(
                '明天再来',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.75)),
              ),
            ],
            const Spacer(),
            if (!signedIn && !busy)
              Text(
                '点我签到',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary),
              ),
          ],
        ),
      ),
    );
  }
}
