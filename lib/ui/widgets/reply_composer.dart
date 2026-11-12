import 'package:flutter/material.dart';

import 'thread_glass.dart';

/// 帖子页底部回复栏。
///
/// 一整块悬浮的玻璃胶囊，从下往上三层：
///
/// ```
/// ╭───────────────────────────────────╮
/// │ ▎回复 Binary_涛 · 3楼          ✕ │  引用条（只在回复某楼时出现）
/// │ 写下你的回复…                  😊 │  输入区（直接写在玻璃上，没有底框）
/// ╰───────────────────────────────────╯
/// ```
///
/// 三层共用一次高斯模糊：早先引用条、输入区、表情面板各自套了一层玻璃，
/// 叠在一起是三次全屏 `BackdropFilter`，低端机上滑一下就掉帧。
class ReplyComposer extends StatefulWidget {
  const ReplyComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onAttach,
    required this.onToggleEmoji,
    required this.onClearReplyTarget,
    this.replyToAuthor,
    this.replyToFloor,
    this.emojiPanel,
    this.attachmentCount = 0,
    this.uploading = false,
    this.sending = false,
    this.showEmoji = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// 正在回复谁；为空表示发的是普通回复。
  final String? replyToAuthor;

  /// 「3楼」这种楼层标签，跟 [replyToAuthor] 一起显示。
  final String? replyToFloor;

  /// 表情面板，`showEmoji` 为真时接在胶囊底部。
  final Widget? emojiPanel;

  /// 已插入正文的图片数量，用来在按钮上挂角标。
  final int attachmentCount;

  final bool uploading;
  final bool sending;
  final bool showEmoji;

  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onToggleEmoji;
  final VoidCallback onClearReplyTarget;

  @override
  State<ReplyComposer> createState() => _ReplyComposerState();
}

class _ReplyComposerState extends State<ReplyComposer> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant ReplyComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
      _onTextChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  /// 只重建输入区这一小块，敲字不会把整页顶着重构。
  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  bool get _replying => widget.replyToAuthor != null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: GlassBackdrop(
        borderRadius: BorderRadius.circular(26),
        // 比顶栏再透一点：键盘弹起时它离正文最近，实了会像块板子。
        opacityScale: 0.92,
        // 不能开 showShadow：那层阴影画在同一个 DecoratedBox 里，玻璃又是
        // 半透明的，阴影会从面板内部透出来，把整块回复栏压成一块灰板子
        // （实测面板比背景还暗 13 级）。玻璃面板的立体感交给描边和高光。
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 引用条从 0 高度长出来，切换回复目标时不会「啪」地跳一下。
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _replying ? _quoteBar(scheme) : const SizedBox(width: double.infinity),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  _emojiButton(scheme),
                  const SizedBox(width: 2),
                  Expanded(child: _inputField()),
                  const SizedBox(width: 2),
                  _attachButton(scheme),
                  const SizedBox(width: 2),
                  _SendButton(
                    enabled: _hasText && !widget.sending,
                    sending: widget.sending,
                    onSend: widget.onSend,
                  ),
                ],
              ),
            ),
            if (widget.showEmoji && widget.emojiPanel != null) ...<Widget>[
              Divider(
                height: 0.6,
                thickness: 0.6,
                indent: 14,
                endIndent: 14,
                color: ThreadGlass.borderColor(context),
              ),
              widget.emojiPanel!,
            ],
          ],
        ),
      ),
    );
  }

  /// 引用条：左边一道主色竖杠，写明回复谁、哪一楼。
  ///
  /// 早先只有一行 11.5 号的小字，压在输入框上面，和输入框本身一样宽、
  /// 一样淡，划过去根本看不出「这条回复是回给谁的」。
  Widget _quoteBar(ColorScheme scheme) {
    final floor = widget.replyToFloor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 0),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 20,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.reply_rounded, size: 15, color: scheme.primary),
          const SizedBox(width: 5),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: '回复 ',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w400),
                  ),
                  TextSpan(
                    text: widget.replyToAuthor,
                    style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
                  ),
                  if (floor != null && floor.isNotEmpty)
                    TextSpan(
                      text: ' · $floor',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w400),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          IconButton(
            tooltip: '取消回复',
            onPressed: widget.onClearReplyTarget,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            icon: Icon(Icons.close_rounded, size: 16, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 输入区：直接写在玻璃上，不再套一层浅色方框。
  ///
  /// 上下各留 10，单行时正好和两侧那两颗 40 高的圆角键齐平；多行时自己往上长，
  /// 两边的键贴底对齐。
  Widget _inputField() {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      minLines: 1,
      maxLines: 5,
      textInputAction: TextInputAction.newline,
      style: const TextStyle(fontSize: 14.5, height: 1.35),
      decoration: const InputDecoration(
        hintText: '写下你的回复…',
        isDense: true,
        contentPadding: EdgeInsets.fromLTRB(8, 10, 8, 10),
        // 只关掉三处边框还不够：`InputDecorationTheme` 里全局 `filled: true`，
        // `filled` 留空就会继承过来，用 `getOuterPath` 在文字区铺一块淡白底——
        // 描边没了，方块还在，看着就是玻璃上贴了一张白纸。这里连底色一起关掉。
        filled: false,
        fillColor: Colors.transparent,
        // 不写 border 时用的是主题里的下划线，玻璃上会横着一条细线，
        // 看着像表单输入格。这里彻底去掉，让人只看到玻璃。
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );
  }

  Widget _emojiButton(ColorScheme scheme) {
    return IconButton(
      tooltip: widget.showEmoji ? '收起表情' : '表情',
      onPressed: widget.onToggleEmoji,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      style: IconButton.styleFrom(
        backgroundColor: widget.showEmoji
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(
        widget.showEmoji ? Icons.keyboard_alt_outlined : Icons.sentiment_satisfied_alt_rounded,
        size: 22,
        color: widget.showEmoji ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }

  Widget _attachButton(ColorScheme scheme) {
    final button = IconButton(
      tooltip: '插入图片',
      onPressed: widget.uploading ? null : widget.onAttach,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: widget.uploading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(Icons.add_photo_alternate_outlined, size: 22, color: scheme.onSurfaceVariant),
    );
    if (widget.attachmentCount <= 0) return button;
    // 图片是插进正文的 BBCode，发出去之前看不到，靠角标记着插了几张。
    // 角标往内收一点，不然会压到右边那颗发送键上。
    return Badge.count(
      count: widget.attachmentCount,
      backgroundColor: scheme.primary,
      textColor: scheme.onPrimary,
      offset: const Offset(-4, 2),
      child: button,
    );
  }
}

/// 发送键：空内容时压暗、敲进一个字就点亮，按下去轻微回缩。
class _SendButton extends StatefulWidget {
  const _SendButton({required this.enabled, required this.sending, required this.onSend});

  final bool enabled;
  final bool sending;
  final VoidCallback onSend;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 发送中按钮保持主色，只是中间换成转圈——压暗会像被禁用。
    final lit = widget.enabled || widget.sending;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: '发送回复',
      child: GestureDetector(
        onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.enabled ? widget.onSend : null,
        child: AnimatedScale(
          scale: _pressed ? 0.9 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: lit ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              boxShadow: lit
                  ? <BoxShadow>[
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.32),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: widget.sending
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary),
                  )
                : Icon(
                    Icons.send_rounded,
                    size: 19,
                    color: lit
                        ? scheme.onPrimary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.45),
                  ),
          ),
        ),
      ),
    );
  }
}
