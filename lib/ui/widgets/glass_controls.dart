import 'package:flutter/material.dart';

import 'thread_glass.dart';

/// 玻璃胶囊的语义色：默认是中性玻璃，[accent] 用主色淡底，表示「已选中 /
/// 这是标签」这类需要被强调的对象。
enum GlassPillTone { neutral, accent }

/// 小玻璃胶囊：筛选条件、标签、联想词都用它。
///
/// 之前搜索页、标签页各写了一套：搜索页是白玻璃 + 主色选中态，标签页是
/// 主色淡底。同样是「一粒圆角小方块」，圆角一个 18 一个 20，按下有没有
/// 反馈也不一样。统一到这里，靠 [tone] 区分语义。
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.trailing,
    this.selected = false,
    this.tone = GlassPillTone.neutral,
    this.fontSize = 12.5,
    this.padding = const EdgeInsets.fromLTRB(12, 7, 12, 7),
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final IconData? trailing;
  final bool selected;
  final GlassPillTone tone;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = tone == GlassPillTone.accent;
    final fg = accent || selected ? scheme.primary : scheme.onSurfaceVariant;
    final fill = accent || selected
        ? scheme.primary.withValues(alpha: isDark ? 0.22 : 0.13)
        : Colors.white.withValues(alpha: isDark ? 0.09 : 0.44);
    final stroke = accent || selected
        ? scheme.primary.withValues(alpha: isDark ? 0.45 : 0.34)
        : ThreadGlass.borderColor(context);

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: fill,
          border: Border.all(color: stroke, width: 0.9),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: padding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: fg),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 2),
                  Icon(trailing, size: 16, color: fg.withValues(alpha: 0.8)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃搜索框：不铺实心底色，只留一圈发丝描边和极淡的白色，
/// 让背后顶栏的模糊透上来。聚焦时描边转主色并带一圈微光。
///
/// 搜索页、浏览历史原来各写一套，一个圆角 23 一个 14、一个白玻璃一个实心灰。
class GlassSearchField extends StatefulWidget {
  const GlassSearchField({
    super.key,
    required this.controller,
    this.hintText = '搜索…',
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.height = 46,
    this.leading = Icons.search_rounded,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final double height;
  final IconData leading;

  @override
  State<GlassSearchField> createState() => _GlassSearchFieldState();
}

class _GlassSearchFieldState extends State<GlassSearchField> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focused == _focus.hasFocus) return;
    setState(() => _focused = _focus.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = scheme.primary.withValues(alpha: isDark ? 0.55 : 0.42);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.height / 2),
        color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.46),
        border: Border.all(
          color: _focused ? accent : ThreadGlass.borderColor(context),
          width: _focused ? 1.2 : 0.9,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: isDark ? 0.28 : 0.18),
                  blurRadius: 14,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(widget.leading, size: 19, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              cursorHeight: 18,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
                ),
              ),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: widget.controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox(width: 12)
                : Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        widget.controller.clear();
                        widget.onChanged?.call('');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.cancel_rounded,
                          size: 17,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 玻璃分段控件：二到六段的小切换（全部/热销、道具分类、帖子/投票）。
///
/// 原来是 Material 的 `SegmentedButton`：直角块、选中态是一条描边轮廓，
/// 放在玻璃卡片旁边像两个时代的东西。这里做成「一整块淡玻璃 + 选中那段
/// 浮起」，和 [GlassPill] 同一套观感。
class GlassSegmented<T> extends StatelessWidget {
  const GlassSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.expand = false,
    this.dense = false,
  });

  /// 值 + 显示文案，按顺序渲染。
  final List<(T, String)> segments;
  final T value;

  /// 传 null 表示整组禁用。
  final ValueChanged<T>? onChanged;

  /// 每段等分容器宽度；为 false 时整组宽度随内容收缩。
  final bool expand;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onChanged != null;
    final radius = BorderRadius.circular(999);

    Widget seg(T key, String label) {
      final active = key == value;
      final fg = !enabled
          ? scheme.onSurfaceVariant.withValues(alpha: 0.45)
          : active
              ? scheme.primary
              : scheme.onSurfaceVariant;
      final body = Material(
        color: active
            ? scheme.primary.withValues(alpha: isDark ? 0.26 : 0.14)
            : Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => onChanged!(key) : null,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 13, vertical: dense ? 6 : 8),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: dense ? 12 : 13.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: fg,
              ),
            ),
          ),
        ),
      );
      return expand ? Expanded(child: body) : body;
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isDark ? 0.07 : 0.36),
        borderRadius: radius,
        border: Border.all(color: ThreadGlass.borderColor(context)),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [for (final s in segments) seg(s.$1, s.$2)],
      ),
    );
  }
}

/// 玻璃表单输入框：发帖、登录这类表单页的通用输入行。
///
/// 这些页面原来直接用 Material 默认的 [InputDecoration]：底下一道下划线、
/// 聚焦时标签上浮、错误时整行变红，跟全站的玻璃卡片是两套语言。统一到
/// 这里：一层极淡的白玻璃、一圈发丝描边，聚焦时描边转主色并带一圈微光，
/// 和 [GlassSearchField] 用同一套反馈。
class GlassField extends StatefulWidget {
  const GlassField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.leading,
    this.trailing,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.obscureText = false,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;

  /// 输入框上方的小标题。原标题是 Material 的浮动 label，聚焦时会跳到边框上，
  /// 玻璃上没有边框可跳，改成常驻的小字更稳。
  final String? label;
  final String? hintText;
  final IconData? leading;

  /// 尾部附加物，比如字数统计、单位。
  final Widget? trailing;
  final int minLines;

  /// 传 null 表示不限行数（正文那种长输入）。
  final int? maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool obscureText;
  final TextCapitalization textCapitalization;

  @override
  State<GlassField> createState() => _GlassFieldState();
}

class _GlassFieldState extends State<GlassField> {
  FocusNode? _ownFocus;
  late bool _focused = widget.focusNode?.hasFocus ?? false;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant GlassField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_onFocusChanged);
      _focus.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focused == _focus.hasFocus) return;
    setState(() => _focused = _focus.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = scheme.primary.withValues(alpha: isDark ? 0.55 : 0.42);
    final multiline = widget.maxLines != 1;

    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.44),
        border: Border.all(
          color: _focused ? accent : ThreadGlass.borderColor(context),
          width: _focused ? 1.2 : 0.9,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: isDark ? 0.26 : 0.16),
                  blurRadius: 14,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment:
            multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (widget.leading != null) ...[
            SizedBox(width: 13),
            Padding(
              padding: EdgeInsets.only(top: multiline ? 15 : 0),
              child: Icon(
                widget.leading,
                size: 18,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(width: 8),
          ] else
            const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              obscureText: widget.obscureText,
              textCapitalization: widget.textCapitalization,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              maxLength: widget.maxLength,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              cursorHeight: multiline ? null : 18,
              style: TextStyle(
                fontSize: 14.5,
                height: multiline ? 1.55 : 1.2,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  fontSize: multiline ? 13.5 : 14,
                  height: multiline ? 1.55 : 1.2,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          if (widget.trailing != null)
            Padding(
              padding: EdgeInsets.only(right: 10, top: multiline ? 14 : 0),
              child: widget.trailing,
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );

    if (widget.label == null) return box;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 7),
          child: Text(
            widget.label!,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
            ),
          ),
        ),
        box,
      ],
    );
  }
}

/// 玻璃选择行：点开一层浮层挑一个值（版块、分类）。
///
/// 原来这种地方用 `DropdownButtonFormField`，展开是一张灰色菜单，和全站
/// 的玻璃浮层不搭；外观上还带下划线和浮动标签，看着像网页表单。
class GlassSelectRow extends StatelessWidget {
  const GlassSelectRow({
    super.key,
    required this.value,
    required this.onTap,
    this.leading,
    this.placeholder = '未选择',
    this.label,
    this.dense = false,
  });

  final String? value;
  final VoidCallback onTap;
  final IconData? leading;
  final String placeholder;
  final String? label;

  /// 压缩上下留白，用在行内（一行里还有别的文字）而不是独立表单行。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final empty = value == null || value!.isEmpty;

    final row = Material(
      color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.44),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: ThreadGlass.borderColor(context)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: dense
              ? const EdgeInsets.fromLTRB(11, 8, 8, 8)
              : const EdgeInsets.fromLTRB(13, 13, 10, 13),
          child: Row(
            children: [
              if (leading != null) ...[
                Icon(
                  leading,
                  size: dense ? 16 : 18,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  empty ? placeholder : value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: empty ? scheme.onSurfaceVariant.withValues(alpha: 0.7) : scheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.unfold_more_rounded,
                size: dense ? 16 : 18,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
              ),
            ],
          ),
        ),
      ),
    );

    if (label == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 7),
          child: Text(
            label!,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
            ),
          ),
        ),
        row,
      ],
    );
  }
}

/// 通用单选浮层：给 [GlassSelectRow] 配的「点开挑一个」。
///
/// 版块这种带分区的列表结构太特殊，仍旧用 `BoardPickerSheet`；这里是给
/// 安全提问这类平铺选项准备的，二十行以内的清单都适用。
Future<T?> showGlassOptionSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.26),
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.68),
        child: GlassBackdrop(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          opacityScale: 1.06,
          showShadow: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 9),
              Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      visualDensity: VisualDensity.compact,
                      tooltip: '关闭',
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                  children: [
                    for (final option in options)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: GlassCard(
                          radius: 14,
                          color: option.$1 == selected
                              ? scheme.primary.withValues(
                                  alpha: Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.13,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(option.$1),
                          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  option.$2,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight:
                                        option.$1 == selected ? FontWeight.w700 : FontWeight.w500,
                                    color: option.$1 == selected
                                        ? scheme.primary
                                        : scheme.onSurface,
                                  ),
                                ),
                              ),
                              if (option.$1 == selected)
                                Icon(Icons.check_rounded, size: 18, color: scheme.primary),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 统一的圆角卡片：底色交给 [Material] 铺，水波纹才不会被外层容器挡住。
///
/// 之前关于页、MCP 页都把 `ListTile` 套在带底色的 `Container` 里，点击时
/// 水波纹画在更外层的 Material 上、被底色盖掉，点下去毫无反馈。
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 18,
    this.color,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: ThreadGlass.borderColor(context)),
    );
    return Material(
      color: color ?? Colors.white.withValues(alpha: isDark ? 0.08 : 0.44),
      clipBehavior: Clip.antiAlias,
      shape: shape,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}
