import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/http_session.dart';
import 'glass_dialog.dart';

/// 弹出「登录 Cookie」对话框，确认复制后返回 true。
///
/// 站点没有开放 token，第三方工具（脚本、桌面端抓取、调试接口）只能照着浏览器
/// 那套走：带上同一份 Cookie 就是同一个人。以前要拿这份东西，只能把手机上的
/// 请求抓下来再手工拼，所以这里直接给一份能原样粘贴的 `name=value; name=value`。
Future<bool> showCookieDialog(BuildContext context, {HttpSession? session}) async {
  final target = session ?? HttpSession.instance;
  final header = target.cookieHeader;
  final count = target.cookieCount;

  final confirmed = await showGlassDialog<bool>(
    context: context,
    builder: (context) => GlassDialog(
      title: const Text('复制 Cookie'),
      content: _CookieContent(header: header, count: count),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(
          onPressed: header.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: header));
                  if (context.mounted) Navigator.pop(context, true);
                },
          child: const Text('复制'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _CookieContent extends StatelessWidget {
  const _CookieContent({required this.header, required this.count});

  final String header;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (header.isEmpty) {
      return const Text('本机还没有存下任何 Cookie。登录之后再来，这里会列出完整的一串。');
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '共 $count 项。粘贴到浏览器或其他客户端，就是当前账号的登录状态，'
          '等同于账号凭证，别发给别人。',
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          // 有的站点会种十几条，全铺开会把对话框顶到屏幕外，这里限高滚动。
          constraints: const BoxConstraints(maxHeight: 190),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              header,
              // 等宽字体：分号、等号密在一起，比例字体读起来容易串行。
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.5,
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
