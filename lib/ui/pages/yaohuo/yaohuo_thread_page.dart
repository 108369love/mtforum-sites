import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../data/yaohuo_repository.dart';
import '../../navigation/app_routes.dart';
import '../internal_browser_page.dart';
import 'yaohuo_login_page.dart';

/// 妖火网原生帖子页：正文 + 回复。
class YaohuoThreadPage extends StatefulWidget {
  const YaohuoThreadPage({super.key, required this.url, this.title = ''});

  final String url;
  final String title;

  @override
  State<YaohuoThreadPage> createState() => _YaohuoThreadPageState();
}

class _YaohuoThreadPageState extends State<YaohuoThreadPage> {
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocus = FocusNode();
  YaohuoThread? _thread;
  final List<YaohuoReply> _replies = <YaohuoReply>[];
  String _moreUrl = '';
  bool _loading = true;
  bool _loadingMore = false;
  bool _notLoggedIn = false;
  bool _sending = false;
  bool _favorited = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  /// 收藏：站点是 POST 表单（带 __CSRFToken），不是 GET 链接。
  Future<void> _favorite() async {
    final thread = _thread;
    if (thread == null) return;
    final ok = await YaohuoRepository.instance.favorite(thread, referer: widget.url);
    if (!mounted) return;
    if (ok) setState(() => _favorited = true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(ok ? '已收藏，可在「我的收藏」里管理' : '收藏失败，可能需要在浏览器里操作')));
  }

  /// 站点回复框的样子：多行输入 + 表情 + 通知楼主 + 发送。
  static const List<({String label, String value})> _faces = <({String label, String value})>[
    (label: '默认', value: ''),
    (label: '开心', value: '哈哈.gif'),
    (label: '支持', value: '酷.gif'),
    (label: '感谢', value: '谢谢.gif'),
    (label: '沙发', value: '沙发.gif'),
    (label: '汗', value: '汗.gif'),
    (label: '思考', value: '思考.gif'),
    (label: '亲亲', value: '亲亲.gif'),
    (label: '囧', value: '囧.gif'),
    (label: '无语', value: '呃.gif'),
    (label: '抱走', value: '抱走.gif'),
  ];

  Future<void> _openComposer() async {
    final thread = _thread;
    if (thread == null) return;
    final controller = TextEditingController(text: _replyController.text);
    var face = '';
    var notify = true;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) {
          final scheme = Theme.of(context).colorScheme;
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('回复帖子', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                const SizedBox(height: 2),
                Text(thread.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 5000,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '请不要乱打字回复，以免被加黑',
                    hintStyle: const TextStyle(fontSize: 13),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _faces.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final item = _faces[index];
                      final selected = face == item.value;
                      return ChoiceChip(
                        label: Text(item.label, style: const TextStyle(fontSize: 12)),
                        selected: selected,
                        onSelected: (_) => setSheet(() => face = item.value),
                      );
                    },
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('通知楼主', style: TextStyle(fontSize: 13)),
                  value: notify,
                  onChanged: (value) => setSheet(() => notify = value),
                ),
                Row(
                  children: [
                    TextButton(onPressed: () => Navigator.pop(sheetContext, false), child: const Text('取消')),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('发送'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    if (confirmed != true) return;
    final content = controller.text.trim();
    if (content.isEmpty) {
      controller.dispose();
      return;
    }
    setState(() => _sending = true);
    final message = await YaohuoRepository.instance.reply(
      thread: thread,
      content: content,
      referer: widget.url,
      face: face,
      notify: notify,
    );
    controller.dispose();
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    if (message.contains('成功')) {
      _replyController.clear();
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _notLoggedIn = false;
    });
    try {
      final thread = await YaohuoRepository.instance.fetchThread(widget.url);
      if (!mounted) return;
      setState(() {
        _thread = thread;
        _replies
          ..clear()
          ..addAll(thread.replies);
        _moreUrl = thread.moreUrl;
        _loading = false;
      });
    } on YaohuoNotLoggedIn {
      if (!mounted) return;
      setState(() {
        _notLoggedIn = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMoreReplies() async {
    if (_loadingMore || _moreUrl.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await YaohuoRepository.instance.fetchReplyPage(_moreUrl);
      if (!mounted) return;
      setState(() {
        _replies.addAll(page.replies);
        _moreUrl = page.moreUrl;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('加载回复失败：$e')));
    }
  }

  void _openBrowser(String url, {String title = '妖火网'}) {
    Navigator.of(context).push(appRoute(builder: (_) => InternalBrowserPage(url: url, title: title)));
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(appRoute(builder: (_) => const YaohuoLoginPage()));
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thread = _thread;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          thread?.title.isNotEmpty == true ? thread!.title : widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (thread != null)
            IconButton(
              tooltip: _favorited ? '已收藏' : '收藏',
              onPressed: _favorite,
              icon: Icon(
                _favorited ? Icons.star_rounded : Icons.star_outline_rounded,
                color: _favorited ? Colors.amber : null,
              ),
            ),
          IconButton(tooltip: '刷新', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
          IconButton(
            tooltip: '用浏览器打开',
            onPressed: () => _openBrowser(widget.url, title: widget.title),
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
        ],
      ),
      body: _buildBody(scheme),
      bottomNavigationBar: _thread == null ? null : _buildReplyBar(scheme),
    );
  }

  Widget _buildReplyBar(ColorScheme scheme) {
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: _sending ? null : _openComposer,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _sending ? '正在发送…' : '回复这个帖子…',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Icon(Icons.send_rounded, size: 20, color: scheme.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_notLoggedIn) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
        children: [
          Icon(Icons.lock_outline_rounded, size: 44, color: scheme.outline),
          const SizedBox(height: 12),
          const Center(child: Text('这篇帖子需要登录后查看', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          const SizedBox(height: 18),
          FilledButton(onPressed: _openLogin, child: const Text('登录妖火')),
        ],
      );
    }
    final thread = _thread;
    if (thread == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
        children: [
          Icon(Icons.cloud_off_rounded, size: 44, color: scheme.outline),
          const SizedBox(height: 12),
          Center(child: Text('读取失败', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.error))),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 18),
          FilledButton(onPressed: _load, child: const Text('重试')),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Text(thread.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.4)),
        const SizedBox(height: 8),
        Text(
          [
            if (thread.board.isNotEmpty) thread.board,
            if (thread.author.isNotEmpty) thread.author,
            if (thread.time.isNotEmpty) thread.time,
            if (thread.reads.isNotEmpty) '阅 ${thread.reads}',
          ].join(' · '),
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        if (thread.bodyText.isNotEmpty) _linkedBody(context, thread.bodyText, scheme),
        if (thread.images.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final image in thread.images)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => _openBrowser(image, title: '图片'),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    image,
                    fit: BoxFit.fitWidth,
                    errorBuilder: (context, error, stack) => Container(
                      padding: const EdgeInsets.all(12),
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      child: Text('图片加载失败：$image', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                    ),
                  ),
                ),
              ),
            ),
        ],
        if (thread.media.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('正文里的媒体', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          for (final item in thread.media)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                item.kind == '音频' ? Icons.audiotrack_rounded : Icons.play_circle_outline_rounded,
                size: 20,
                color: scheme.primary,
              ),
              title: Text(item.kind, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(item.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
              trailing: Icon(Icons.open_in_new_rounded, size: 16, color: scheme.outline),
              onTap: () => _openBrowser(item.url, title: item.kind),
            ),
        ],
        if (thread.links.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('正文里的链接', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          for (final link in thread.links)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(Icons.link_rounded, size: 18, color: scheme.primary),
              title: Text(link.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              subtitle: Text(link.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
              onTap: () => _openBrowser(link.url, title: link.text),
            ),
        ],
        const SizedBox(height: 18),
        Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        const SizedBox(height: 6),
        Text('回复 ${_replies.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        for (final reply in _replies) _replyTile(reply, scheme),
        if (_moreUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(onPressed: _loadMoreReplies, child: const Text('加载更多回复')),
            ),
          ),
        if (_replies.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('还没有回复', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
      ],
    );
  }

  /// 正文里裸写的网址也要能点：按 URL 切段，命中段加下划线和点击。
  Widget _linkedBody(BuildContext context, String text, ColorScheme scheme) {
    final pattern = RegExp(r'https?://[^\s，。、；）)]+');
    final spans = <InlineSpan>[];
    var index = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > index) spans.add(TextSpan(text: text.substring(index, match.start)));
      final url = match.group(0) ?? '';
      if (url.isNotEmpty) {
        spans.add(TextSpan(
          text: url,
          style: TextStyle(color: scheme.primary, decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()..onTap = () => _openBrowser(url, title: url),
        ));
      }
      index = match.end;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));
    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(fontSize: 14, height: 1.75, color: scheme.onSurface),
    );
  }

  Widget _replyTile(YaohuoReply reply, ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (reply.floor.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(reply.floor, style: TextStyle(fontSize: 10, color: scheme.primary, fontWeight: FontWeight.w700)),
                ),
              if (reply.floor.isNotEmpty) const SizedBox(width: 6),
              Expanded(
                child: Text(reply.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              if (reply.time.isNotEmpty)
                Text(reply.time, style: TextStyle(fontSize: 10, color: scheme.outline)),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(reply.content, style: const TextStyle(fontSize: 13, height: 1.6)),
        ],
      ),
    );
  }
}
