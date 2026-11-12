import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../../data/smilies.dart';

/// 在光标处插入文本；光标无效时追加到末尾。
void insertAtCursor(TextEditingController controller, String text) {
  final value = controller.value;
  final selection = value.selection;
  if (!selection.isValid || selection.start < 0 || selection.end < 0) {
    final next = '${value.text}$text';
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    return;
  }
  final start = selection.start;
  final end = selection.end;
  final next = value.text.replaceRange(start, end, text);
  controller.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}

/// 插入 BBCode 包裹，并把光标放在中间。
void insertWrapped(TextEditingController controller, String open, String close) {
  final value = controller.value;
  final selection = value.selection;
  final offset = selection.isValid ? selection.end : value.text.length;
  final inserted = '$open$close';
  final next = value.text.replaceRange(offset, offset, inserted);
  controller.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: offset + open.length),
  );
}

/// 官方表情面板：与网页版发帖框一致的三套自带表情（默认 / 滑稽 / Doge）。
class EmojiPanel extends StatefulWidget {
  const EmojiPanel({super.key, required this.onSelected, this.height = 236});

  final ValueChanged<String> onSelected;
  final double height;

  @override
  State<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  int _setIndex = 0;

  Map<String, String> get _headers {
    final cookie = HttpSession.instance.cookieHeader;
    return {
      'Referer': AppConfig.base,
      'User-Agent': AppConfig.userAgent,
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final set = kSmileySets[_setIndex];
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              itemCount: kSmileySets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final active = index == _setIndex;
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _setIndex = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? scheme.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      kSmileySets[index].name,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: set.items.length,
              itemBuilder: (context, index) {
                final smiley = set.items[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => widget.onSelected(smiley.code),
                  child: Center(
                    child: Image.network(
                      set.urlOf(smiley),
                      width: 28,
                      height: 28,
                      headers: _headers,
                      errorBuilder: (_, __, ___) => Text(
                        smiley.code.replaceAll(RegExp(r'[\[\]]'), ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
