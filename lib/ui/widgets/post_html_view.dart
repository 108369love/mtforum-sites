import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' as parser;

import '../../core/app_config.dart';
import '../../core/forum_link.dart';
import '../../core/http_session.dart';
import '../../core/video_link.dart';
import '../../state/app_state.dart';
import '../pages/board_threads_page.dart';
import '../pages/image_viewer_page.dart';
import '../pages/internal_browser_page.dart';
import '../pages/thread_page.dart';
import '../pages/user_page.dart';
import '../pages/video_player_page.dart';
import 'code_highlight.dart';
import 'smart_image.dart';
import 'video_card.dart';
import '../navigation/app_routes.dart';

/// 将论坛帖子的 HTML 内容解析为原生 Flutter 组件。
class PostHtmlView extends StatefulWidget {
  const PostHtmlView({
    super.key,
    required this.html,
    this.images = const <String>[],
    this.onReply,
    this.selectable = true,
  });

  final String html;
  final List<String> images;
  final VoidCallback? onReply;

  /// 正文是否可长按选择/复制。
  ///
  /// 开启时整楼共用**一个** [SelectionArea]，而不是每段挂一个 SelectableText：
  /// 长图文帖动辄三四百段文字，逐段挂选择器会让滚动时的命中测试与重绘逐段走一遍。
  final bool selectable;

  @override
  State<PostHtmlView> createState() => _PostHtmlViewState();
}

class _PostHtmlViewState extends State<PostHtmlView> {
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];
  List<Widget>? _cache;

  /// 正文按块分批上屏，见 [_blocksPerChunk]。
  List<List<Widget>>? _chunks;
  int _visibleChunks = 1;
  bool _chunkScheduled = false;

  /// 每帧最多新铺多少个正文块。
  ///
  /// 长图文帖一楼就有三百多个 widget，一次性全铺开要 300ms 上下：点开帖子
  /// 那一下正好撞上转场，画面会定住半秒。分帧铺开，每帧只多做一块，十来帧
  /// 铺完；用户这时还在看顶部，看不出差别。
  static const int _blocksPerChunk = 24;

  /// 正文配色改了要重排：[_cache] 里存的是已经带上色的 span。
  Color? _lastLinkColor;
  Color? _lastHintColor;

  @override
  void initState() {
    super.initState();
    _lastLinkColor = AppState.instance.readLinkColor;
    _lastHintColor = AppState.instance.readHintColor;
    AppState.instance.addListener(_onReadPaletteChanged);
  }

  void _onReadPaletteChanged() {
    final state = AppState.instance;
    if (state.readLinkColor == _lastLinkColor && state.readHintColor == _lastHintColor) return;
    _lastLinkColor = state.readLinkColor;
    _lastHintColor = state.readHintColor;
    if (!mounted) return;
    setState(_reset);
  }

  /// 丢掉已解析的内容，下一次 build 重新解析、重新分帧。
  void _reset() {
    _disposeRecognizers();
    _cache = null;
    _chunks = null;
    _visibleChunks = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reset();
  }

  @override
  void didUpdateWidget(covariant PostHtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) _reset();
  }

  /// 排下一帧再铺一块。
  ///
  /// 只在还有没铺完的块时排队；[_chunks] 被重置后这里的回调会自行退出，
  /// 不会拿旧的分块继续铺。
  void _scheduleNextChunk() {
    if (_chunkScheduled) return;
    _chunkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chunkScheduled = false;
      final chunks = _chunks;
      if (!mounted || chunks == null || _visibleChunks >= chunks.length) return;
      setState(() => _visibleChunks++);
    });
  }

  List<List<Widget>> _split(List<Widget> blocks) {
    final chunks = <List<Widget>>[];
    for (var i = 0; i < blocks.length; i += _blocksPerChunk) {
      chunks.add(blocks.sublist(i, math.min(i + _blocksPerChunk, blocks.length)));
    }
    return chunks;
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onReadPaletteChanged);
    _disposeRecognizers();
    super.dispose();
  }

  /// 正文链接用的颜色：默认跟随主题色，用户可以在「阅读配色」里改。
  Color _linkColor(BuildContext context) =>
      AppState.instance.readLinkColorOf(Theme.of(context).colorScheme);

  /// 「回复可见 / 需要回复」提示用的颜色。
  Color _hintColor(BuildContext context) =>
      AppState.instance.readHintColorOf(Theme.of(context).colorScheme);

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  /// 页面里的隐藏层（附件弹层、模板占位等）不该出现在正文里。
  /// Discuz 的附件提示层就是 `style="display:none"` 的 div，里面装着缩略图和
  /// 下载链接；照常渲染会凭空多出图片占位块，视觉上就是一片空白。
  bool _isHidden(dom.Element element) {
    if (element.attributes.containsKey('hidden')) return true;
    final style = (element.attributes['style'] ?? '').replaceAll(' ', '').toLowerCase();
    if (style.isEmpty) return false;
    return style.contains('display:none') || style.contains('visibility:hidden');
  }

  /// 脚本与样式内容不是正文，直接跳过；否则会把 JS/CSS 原样当段落显示。
  bool _isSkippedTag(String tag) =>
      const {'script', 'style', 'noscript', 'template', 'link', 'meta'}.contains(tag);

  bool _isBlockTag(String tag) => const {
        'div', 'p', 'section', 'article', 'blockquote', 'pre', 'ul', 'ol',
        'table', 'hr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'iframe', 'video',
        'audio', 'center',
      }.contains(tag);

  bool _isSmiley(dom.Element img) {
    final src = (img.attributes['src'] ?? img.attributes['comiis_loadimages'] ?? '').toLowerCase();
    if (src.contains('/smiley/') || src.contains('smiley') || src.contains('smilies')) return true;
    final width = double.tryParse(img.attributes['width'] ?? '');
    final height = double.tryParse(img.attributes['height'] ?? '');
    if (width == null || height == null) return false;
    return width > 0 && height > 0 && width <= 32 && height <= 32;
  }

  String _imageUrl(dom.Element img) {
    final raw = (img.attributes['comiis_loadimages'] ??
            img.attributes['data-src'] ??
            img.attributes['data-original'] ??
            img.attributes['file'] ??
            img.attributes['src'] ??
            img.attributes['longdesc'] ??
            '')
        .trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('file://')) return raw;
    if (raw.contains('none.png') || raw.contains('imageloading.gif') || raw.contains('noavatar')) {
      final candidates = <String>[
        img.attributes['data-src']?.trim() ?? '',
        img.attributes['data-original']?.trim() ?? '',
        img.attributes['file']?.trim() ?? '',
        img.attributes['comiis_loadimages']?.trim() ?? '',
        img.attributes['longdesc']?.trim() ?? '',
      ];
      for (final candidate in candidates) {
        if (candidate.isNotEmpty && !candidate.contains('none.png') && !candidate.contains('imageloading.gif') && !candidate.contains('noavatar')) {
          return AppConfig.uri(candidate).toString();
        }
      }
    }
    return AppConfig.uri(raw).toString();
  }

  List<Widget> _blocks(BuildContext context, List<dom.Node> nodes) {
    final widgets = <Widget>[];
    final inline = <InlineSpan>[];

    void flush() {
      if (inline.isEmpty) return;
      final spans = List<InlineSpan>.from(inline);
      inline.clear();
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(
          TextSpan(children: spans),
          style: TextStyle(
            fontSize: 15.5,
            height: 1.62,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ));
    }

    for (final node in nodes) {
      if (node is dom.Text) {
        final text = _cleanInline(node.text);
        if (text.trim().isEmpty) continue;
        _appendText(context, text, inline, widgets, flush);
        continue;
      }
      if (node is! dom.Element) continue;

      final tag = node.localName ?? '';
      if (_isSkippedTag(tag) || _isHidden(node)) continue;
      if (tag == 'br') {
        if (inline.isNotEmpty) inline.add(const TextSpan(text: '\n'));
        continue;
      }
      // 附件图片常被 <a> 包裹，整块渲染，避免被当成行内元素丢掉。
      if (tag == 'a' && node.querySelector('img') != null) {
        final imgs = node.querySelectorAll('img');
        flush();
        for (final img in imgs) {
          if (_isSmiley(img)) continue;
          final image = _imageBlock(context, img);
          if (image != null) widgets.add(image);
        }
        final text = node.text.trim();
        if (text.isNotEmpty) inline.add(TextSpan(text: text));
        continue;
      }
      // 整段就是一个视频链接时，直接把这块换成可点击播放的区域。
      if (tag == 'a' && node.querySelector('img') == null) {
        final href = node.attributes['href'] ?? '';
        final video = href.isEmpty ? null : parseVideoLink(AppConfig.uri(href).toString());
        if (video != null) {
          final text = node.text.trim();
          // 链接文字是「视频演示」这类短标题、或者干脆就是链接本身，就做成播放区域；
          // 一整句话里夹着的链接保持行内样式，点击时同样走应用内播放。
          final standalone = text.isEmpty ||
              text == href ||
              parseStandaloneVideo(text) != null ||
              (text.length <= 20 && !text.contains(RegExp(r'[。！？!?\n]')));
          if (standalone) {
            flush();
            widgets.add(_videoCard(context, video, title: _videoLabel(text)));
            continue;
          }
        }
      }
      if (tag == 'img') {
        if (_isSmiley(node)) {
          final src = _imageUrl(node);
          if (src.isNotEmpty) {
            inline.add(WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Image.network(
                  src,
                  width: 22,
                  height: 22,
                  headers: _headers(),
                  errorBuilder: (_, __, ___) => const SizedBox(width: 22, height: 22),
                ),
              ),
            ));
          }
        } else {
          flush();
          final image = _imageBlock(context, node);
          if (image != null) widgets.add(image);
        }
        continue;
      }

      // [hide] 的壳子跟引用块长得一样，先认出来，否则会被当引用渲染成一片
      // 灰字纯文本，链接也点不了。
      if (_isHiddenContentBlock(node)) {
        flush();
        widgets.add(_hiddenContentCard(context, node));
        continue;
      }

      // 引用块要优先于普通容器处理：站点皮肤常把 [quote] 渲染成
      // div.quote（没有 blockquote），不拦截就会退化成一整段正文。
      if (_isQuoteContainer(tag, node.classes) || _looksLikeQuotedBlock(node, tag)) {
        flush();
        widgets.add(_quoteCard(context, node));
        continue;
      }

      if (_isBlockTag(tag)) {
        flush();
        widgets.addAll(_blockElement(context, node));
        continue;
      }

      // 行内元素里包着的图片（`<span class="comiis_postimg"><img></span>` 是最常见
      // 的形态，手机模板的附件图都是这么包的）不能当行内元素处理。
      //
      // 塞进 Text 的 WidgetSpan 后，图片按整行宽度铺开、高度按原图比例算：
      // 一张 1080×4252 的截图会给这一段排出一千三百多像素的行高，而这一行里
      // 的文字按行内对齐垂直居中——于是正文里凭空多出上下好几屏空白，长按也
      // 选不中（那是图片容器，不是文字）。整块递归下去，让图片走块级路径。
      if (node.querySelectorAll('img').any((img) => !_isSmiley(img))) {
        flush();
        widgets.addAll(_blocks(context, node.nodes));
        continue;
      }

      inline.addAll(_inlineNode(context, node, TextStyle(
        fontSize: 15.5,
        height: 1.62,
        color: Theme.of(context).colorScheme.onSurface,
      )));
    }
    flush();
    return widgets;
  }

  /// 文本节点里的视频链接有两种归宿：
  /// 单独成行的换成播放卡片，混在句子里的保持行内可点链接（点击也走应用内播放）。
  void _appendText(
    BuildContext context,
    String text,
    List<InlineSpan> inline,
    List<Widget> widgets,
    void Function() flush,
  ) {
    final style = TextStyle(
      fontSize: 15.5,
      height: 1.62,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i > 0 && inline.isNotEmpty) inline.add(const TextSpan(text: '\n'));
      if (line.trim().isEmpty) continue;
      final video = parseStandaloneVideo(line);
      if (video != null) {
        flush();
        widgets.add(_videoCard(context, video, title: _videoLabel(line)));
        continue;
      }
      if (_isReplyHint(line)) {
        inline.addAll(_linkifyText(
          context,
          line,
          style.copyWith(color: _hintColor(context), fontWeight: FontWeight.w600),
        ));
        continue;
      }
      inline.addAll(_linkifyText(context, line, style));
    }
  }

  /// 「回复可见 / 需要回复」这类提示，各套手机模板的文案都不一样。
  ///
  /// 论坛帖子动辄几十上百行，这类提示夹在正文里和普通文字一个颜色，长文
  /// 很容易划过去。命中就整行换成提示色并加粗，颜色由「阅读配色」决定。
  ///
  /// 匹配必须卡在段首：以前只要句子里出现「回复」「隐藏内容」就整段染色，
  /// 于是「把需要回复和链接改个颜色吗」这种正常讨论、以及「且建议增加帖子
  /// 隐藏内容中检测链接」这类建议，全被染成提示色，一屏花花绿绿反而更难看。
  /// 现在只认「这段本身就是提示」——提示语在开头，或整句以「回复可见」收尾。
  static final RegExp _replyHintPattern = RegExp(
    r'^(?:(?:本帖)?(?:隐藏的内容|隐藏内容|隐藏部分|以下内容|附件|内容)\s*[：:，,。]?\s*)?'
    r'(?:需要)?(?:回复|登录)(?:后|才能|方可|即可|可见|浏览|查看)'
    r'|^(?:请先)?回复本帖'
    r'|^查看本帖隐藏'
    r'|(?:回复可见|回复后可见|登录可见)$',
    caseSensitive: false,
  );

  bool _isReplyHint(String line) => _replyHintPattern.hasMatch(line.trim());

  Widget _videoCard(BuildContext context, VideoLink video, {String? title}) {
    return VideoCard(
      video: video,
      title: title,
      onOpenExternal: () => _openInBrowser(video.url),
    );
  }

  Future<void> _openInBrowser(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 从「视频演示：https://…」里取出前半句说明，作为卡片标题。
  String? _videoLabel(String text) {
    final withoutUrl = text.replaceAll(RegExp(r'https?://\S+'), '').trim();
    final cleaned = withoutUrl.replaceAll(RegExp(r'[：:，,。.、；;\-—\s]+$'), '').replaceAll(RegExp(r'^[「『“"（(\[]+'), '').trim();
    if (cleaned.isEmpty || cleaned.length > 20) return null;
    // 「点我播放」「点击观看」这类只是操作指令，不算说明，卡片用默认标题。
    if (cleaned.length <= 8 && RegExp(r'^(点我|点击|点此|直接)?(播放|观看)').hasMatch(cleaned)) return null;
    return cleaned;
  }

  void _openVideo(BuildContext context, VideoLink video, [String? title]) {
    Navigator.of(context).push(appRoute(
      builder: (_) => VideoPlayerPage(video: video, title: title),
    ));
  }

  List<Widget> _blockElement(BuildContext context, dom.Element element) {
    final tag = element.localName ?? '';
    final classes = element.classes;

    if (tag == 'blockquote') {
      if (_isHiddenContentBlock(element)) return [_hiddenContentCard(context, element)];
      return [_quoteCard(context, element)];
    }

    if (tag == 'pre' || classes.contains('blockcode')) {
      final text = element.text.trim();
      if (text.isEmpty) return const [];
      return [
        _codeBlock(context, text, <String>[
          ...classes,
          ...?element.querySelector('code')?.classes,
        ]),
      ];
    }

    if (tag == 'ul' || tag == 'ol') {
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, li) in element.querySelectorAll('li').indexed)
                _listItem(context, li, marker: tag == 'ol' ? '${index + 1}.' : '•'),
            ],
          ),
        ),
      ];
    }

    if (tag == 'table') {
      return [_tableBlock(context, element)];
    }

    if (tag == 'hr') {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Divider(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ];
    }

    if (RegExp(r'^h[1-6]$').hasMatch(tag)) {
      final spans = _inlineNode(context, element, TextStyle(
        fontSize: 17,
        height: 1.45,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ));
      return [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text.rich(TextSpan(children: spans), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.45)),
        ),
      ];
    }

    if (tag == 'iframe' || tag == 'video') {
      final src = element.attributes['src'] ?? element.querySelector('source')?.attributes['src'] ?? '';
      if (src.isEmpty) return const [];
      final resolved = AppConfig.uri(src).toString();
      final video = parseVideoLink(resolved) ??
          VideoLink(url: resolved, kind: VideoKind.other, playUrl: resolved, asPage: true);
      return [_videoCard(context, video)];
    }

    if (tag == 'audio') {
      final src = element.attributes['src'] ?? element.querySelector('source')?.attributes['src'] ?? '';
      if (src.isEmpty) return const [];
      return [
        Card(
          child: ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('音频内容'),
            subtitle: Text(src, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.of(context).push(appRoute(builder: (_) => InternalBrowserPage(url: AppConfig.uri(src).toString(), title: '音频内容'))),
          ),
        ),
      ];
    }

    if (tag == 'div' && classes.contains('comiis_p10')) {
      final hint = _hintColor(context);
      return [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: hint.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hint.withValues(alpha: 0.28), width: 0.8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: hint),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: _inlineNode(context, element, TextStyle(
                    fontSize: 13.5,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                    color: hint,
                  ))),
                  style: const TextStyle(fontSize: 13.5, height: 1.55),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    // 普通容器：递归渲染内部块。
    return _blocks(context, element.nodes);
  }

  /// 列表项：整项就是一个视频链接时换成播放卡片，其余照旧一行文本。
  Widget _listItem(BuildContext context, dom.Element li, {required String marker}) {
    final video = _standaloneVideoIn(li);
    if (video != null) {
      // 卡片自己带边框，项目符号就省了，只留和正文对齐的缩进。
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 0, 5),
        child: _videoCard(context, video, title: _videoLabel(li.text.trim())),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            marker,
            style: TextStyle(fontSize: 15, height: 1.5, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text.rich(
              TextSpan(children: _inlineNode(context, li, TextStyle(
                fontSize: 15,
                height: 1.58,
                color: Theme.of(context).colorScheme.onSurface,
              ))),
              style: const TextStyle(fontSize: 15, height: 1.58),
            ),
          ),
        ],
      ),
    );
  }

  /// 列表项里只有一个视频链接时把它取出来。
  ///
  /// 「▍视频教程」下面常见写法就是 `<li><a href="bilibili…">点我播放</a></li>`，
  /// 整项没有别的字，做成播放区域比留一条蓝色链接顺手。
  VideoLink? _standaloneVideoIn(dom.Element item) {
    if (item.querySelector('img, iframe, video, audio, ul, ol, table') != null) return null;
    final links = item.querySelectorAll('a').where((a) => a.querySelector('img') == null).toList();
    if (links.length != 1) return null;
    final link = links.first;
    final href = link.attributes['href'] ?? '';
    if (href.isEmpty) return null;
    final video = parseVideoLink(AppConfig.uri(href).toString());
    if (video == null) return null;
    final text = link.text.trim();
    // 链接之外还有别的字，说明是句子里的链接，保持行内样式。
    if (item.text.replaceFirst(text, '').trim().isNotEmpty) return null;
    final standalone = text.isEmpty ||
        text == href ||
        parseStandaloneVideo(text) != null ||
        (text.length <= 20 && !text.contains(RegExp(r'[。！？!?\n]')));
    return standalone ? video : null;
  }

  /// 引用容器：标准的 blockquote，以及皮肤改写后的 div.quote 等。
  bool _isQuoteContainer(String tag, Set<String> classes) {
    if (tag == 'blockquote') return true;
    if (!const {'div', 'section', 'article', 'fieldset'}.contains(tag)) return false;
    return classes.any((name) =>
        name == 'quote' ||
        name == 'blockquote' ||
        name == 'quotecontent' ||
        name == 'comiis_quote' ||
        name.endsWith('_quote'));
  }

  /// 有些皮肤连 quote 类名都不给：叶子里只有一行「某某 发表于 …」再跟正文，
  /// 这类容器同样按引用处理。约束得足够紧，避免把本楼正文吞进卡片。
  bool _looksLikeQuotedBlock(dom.Element element, String tag) {
    if (!const {'div', 'section', 'dl'}.contains(tag)) return false;
    if (element.querySelector('div, p, ul, ol, table, blockquote, fieldset') != null) return false;
    final text = _cleanInline(element.text).trim();
    if (text.isEmpty || text.length > 1500) return false;
    final head = text.length > 48 ? text.substring(0, 48) : text;
    return RegExp(r'^[^。！？]{1,40}?发表于').hasMatch(head);
  }

  /// 「本帖隐藏的内容」区块，含已解锁和还没解锁两种形态。
  ///
  /// Discuz 的 [hide] 在各套模板里的外壳不一样（blockquote、div.quote、fieldset
  /// 都见过）：解锁后正文以「本帖隐藏的内容」开头，没解锁时整段是一句提示
  /// （「某某，如果您要查看本帖隐藏内容请回复」）。以前两种都落进引用卡当纯文本
  /// 渲染：灰字灰底、里面的链接也点不了，长帖里一划就过去。
  static final RegExp _hideContentLabel = RegExp(r'^本帖隐藏的内容');

  /// 未解锁的提示句。抓的是「隐藏内容 + 请回复」这种搭配，而不是只要出现
  /// 「隐藏内容」——回帖里正常讨论这四个字的句子不能被算成提示。
  static final RegExp _hideHintPattern = RegExp(
    r'(?:本帖)?隐藏内容?\s*[，,]?\s*(?:请回复|需要回复|回复后|回复才能)'
    r'|如果您?要查看本帖隐藏内容'
    r'|回复(?:后|才能)(?:查看|浏览|可见)',
    caseSensitive: false,
  );

  bool _isHiddenContentBlock(dom.Element element) {
    final tag = element.localName ?? '';
    if (!const {'div', 'section', 'article', 'blockquote', 'fieldset'}.contains(tag)) {
      return false;
    }
    final text = _cleanInline(element.text).trim();
    if (text.isEmpty || text.length > 800) return false;
    // 引用别人的楼层里也会出现这句话，带「发表于」头的还是按引用走。
    if (text.contains('发表于')) return false;
    if (_hideContentLabel.hasMatch(text)) return true;
    // 未解锁提示就是一整句话，长段落里夹带的不算。
    if (text.length > 100) return false;
    return _hideHintPattern.hasMatch(text);
  }

  /// 去掉开头那句「本帖隐藏的内容」：它已经提到卡片标题上，正文再留一遍就重复了。
  List<dom.Node> _withoutHideLabel(List<dom.Node> nodes) {
    final kept = <dom.Node>[];
    var stripped = false;
    for (final node in nodes) {
      if (!stripped && node is dom.Text && _hideContentLabel.hasMatch(_cleanInline(node.text).trim())) {
        stripped = true;
        final rest = node.text.replaceFirst(
          RegExp(r'^\s*本帖隐藏的内容\s*[：:，,。、]?\s*'),
          '',
        );
        if (rest.trim().isNotEmpty) kept.add(dom.Text(rest));
        continue;
      }
      kept.add(node);
    }
    return kept;
  }

  /// 一栋楼里可能同时出现「未解锁提示」和「已解锁内容」，所以别给这张卡加
  /// 固定 Key：同层出现两个相同 Key 会直接断言失败，整楼降级成纯文本。
  Widget _hiddenContentCard(BuildContext context, dom.Element element) {
    final accent = _hintColor(context);
    final raw = _cleanInline(element.text).trim();
    // 已经解锁：正文以「本帖隐藏的内容」开头，这句提到标题上，剩下的才是内容。
    final unlocked = _hideContentLabel.hasMatch(raw);
    final lock = Icon(Icons.lock_outline_rounded, size: 15, color: accent);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2, bottom: 10),
      padding: EdgeInsets.fromLTRB(12, 10, 12, unlocked ? 4 : 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: unlocked
            ? [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      lock,
                      const SizedBox(width: 5),
                      Text(
                        '本帖隐藏的内容',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
                ..._blocks(context, _withoutHideLabel(element.nodes)),
              ]
            : [
                // 还没解锁：整句就是一条提示，拆成标题会把话截断，索性整句加粗，
                // 前面挂把锁，跟已解锁的卡片是同一套颜色。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(padding: const EdgeInsets.only(top: 2), child: lock),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        raw,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
      ),
    );
  }

  /// 引用按网页端 .quote 的样子渲染：左边一条灰竖线 + 浅灰底，
  /// 头部是「作者 发表于 时间」（作者可点进主页），正文完整展示。
  Widget _quoteCard(BuildContext context, dom.Element element) {
    final parts = _quoteParts(element);
    if (parts.author.isEmpty && parts.body.isEmpty) {
      // 引用里只有图片等情况，退回普通渲染，至少让图片可见。
      final blocks = _blocks(context, element.nodes);
      if (blocks.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
    }
    return _QuoteCard(
      author: parts.author,
      time: parts.time,
      body: parts.body,
      onTapAuthor: parts.uid > 0 ? () => _openUser(context, parts.uid, parts.author) : null,
    );
  }

  /// 拆出引用头里的作者、时间和引用正文。
  ({String author, int uid, String time, String body}) _quoteParts(dom.Element element) {
    final headNode = _findQuoteHead(element);
    var author = '';
    var uid = 0;
    var time = '';

    if (headNode != null) {
      // 网页端把作者包成链接，时间跟在后面：<font><a>作者</a> 发表于 …</font>
      // 也有模板把整句都塞进链接，这时不能整段当昵称，交给下面的正则拆。
      final link = headNode.querySelector('a[href]');
      if (link != null) {
        final linkText = _cleanInline(link.text);
        uid = _uidFromHref(link.attributes['href'] ?? '');
        if (linkText.isNotEmpty && !linkText.contains('发表于')) author = linkText;
      }
      final raw = _cleanInline(headNode.text);
      final match = RegExp(r'^(.*?)\s*发表于\s*(.*)$').firstMatch(raw);
      if (match != null) {
        if (author.isEmpty) author = _cleanInline(match.group(1) ?? '');
        time = _cleanInline(match.group(2) ?? '');
      } else {
        time = raw;
      }
      // 引用头的链接是跳转地址（没有 uid）时，退一步找同名的空间链接。
      if (uid <= 0 && author.isNotEmpty) {
        for (final link in element.querySelectorAll('a[href]')) {
          if (_cleanInline(link.text) != author) continue;
          final id = _uidFromHref(link.attributes['href'] ?? '');
          if (id > 0) {
            uid = id;
            break;
          }
        }
      }
    }

    final raw = _quoteText(element, skip: headNode);
    final lines = raw
        .split('\n')
        .map(_cleanInline)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    // 引用头没被单独包起来时，它就是正文第一行。
    if (headNode == null && lines.isNotEmpty && lines.first.contains('发表于')) {
      final head = lines.removeAt(0);
      final match = RegExp(r'^(.*?)\s*发表于\s*(.*)$').firstMatch(head);
      if (match != null) {
        author = _cleanInline(match.group(1) ?? '');
        time = _cleanInline(match.group(2) ?? '');
      } else {
        author = head;
      }
    }
    return (author: author, uid: uid, time: time, body: lines.join('\n').trim());  }

  /// 找到承载「某某 发表于 …」的那层节点，尽量取最内层，避免把正文算进头部。
  dom.Element? _findQuoteHead(dom.Element element) {
    dom.Element? found;
    void walk(dom.Element node) {
      if (found != null) return;
      if (_cleanInline(node.text).contains('发表于')) {
        var inner = node;
        while (true) {
          final deeper = [
            for (final child in inner.children)
              if (_cleanInline(child.text).contains('发表于')) child,
          ];
          if (deeper.isEmpty) break;
          inner = deeper.first;
        }
        found = inner;
        return;
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final child in element.children) {
      walk(child);
      if (found != null) break;
    }
    return found;
  }

  int _uidFromHref(String href) {
    final match = RegExp(r'(?:[?&](?:amp;)?uid=|space-uid-)(\d+)').firstMatch(href);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  void _openUser(BuildContext context, int uid, String name) {
    if (uid <= 0) return;
    Navigator.of(context).push(appRoute(builder: (_) => UserPage(uid: uid, name: name)));
  }

  /// 引用正文的纯文本：保留换行，丢掉图片（引用里的原图会重复占屏）。
  String _quoteText(dom.Element element, {dom.Element? skip}) {
    final buffer = StringBuffer();
    void walk(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(node.text);
        return;
      }
      if (node is! dom.Element) return;
      if (identical(node, skip)) {
        buffer.write('\n');
        return;
      }
      final tag = node.localName ?? '';
      if (tag == 'br') {
        buffer.write('\n');
        return;
      }
      if (tag == 'img' || tag == 'script' || tag == 'style') return;
      for (final child in node.nodes) {
        walk(child);
      }
      if (const {'div', 'p', 'blockquote', 'li', 'tr', 'fieldset', 'table'}.contains(tag)) {
        buffer.write('\n');
      }
    }

    for (final node in element.nodes) {
      walk(node);
    }
    return buffer.toString();
  }

  /// 代码块：左上角标语言和行数，左侧行号，右侧横向滚动的高亮正文。
  ///
  /// 行号列和正文共用 [CodeHighlight.codeStyle]，也共用同一个 `textScaler`：
  /// 少一样，用户把系统字体调大之后两列就会逐行错开，越往下错得越离谱。
  Widget _codeBlock(BuildContext context, String text, Iterable<String> classes) {
    final scheme = Theme.of(context).colorScheme;
    final language = CodeHighlight.detect(text, classes: classes);
    final lineCount = '\n'.allMatches(text).length + 1;
    final textScaler = MediaQuery.textScalerOf(context);
    // 等宽字体 12.5 号，一个数字大约 7.5 宽；再加 4 的余量，别贴边。
    final gutterWidth =
        (4 + 7.6 * '$lineCount'.length) * (textScaler.scale(12.5) / 12.5);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.brightness == Brightness.dark ? const Color(0xFF0B0E13) : const Color(0xFF1D232B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 0),
            child: Row(
              children: [
                Text(
                  '${language.label} · $lineCount 行',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('代码已复制')),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    minimumSize: const Size(44, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('复制', style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: gutterWidth,
                  child: Text(
                    CodeHighlight.lineNumbers(lineCount),
                    textAlign: TextAlign.right,
                    style: CodeHighlight.codeStyle.copyWith(color: CodeHighlight.gutterColor),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    // 用 Text.rich 而不是裸 RichText：后者不参与外层的
                    // SelectionArea，正文能长按选，代码块却选不了。
                    child: Text.rich(CodeHighlight.span(text, language)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 估算一段文本排成一行大概多宽，用来给表格分列。
  ///
  /// 不需要精确，只要比例对得上：全角按 1 个字宽，半角按 0.55 个字宽。
  /// 超长单元格直接截断计算——最终宽度会被 clamp，算到底也没意义。
  double _textWidth(String text, double fontSize) {
    var units = 0.0;
    for (final rune in text.runes) {
      units += (rune >= 0x2E80 && rune <= 0xFFEF) ? 1.0 : 0.55;
      if (units > 60) break;
    }
    return units * fontSize;
  }

  Widget _tableBlock(BuildContext context, dom.Element table) {
    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final columnCount = rows.map((row) => row.querySelectorAll('td,th').length).fold(0, (a, b) => a > b ? a : b);
    if (columnCount == 0) return const SizedBox.shrink();

    const fontSize = 12.5;

    // 每列按最长的那个单元格估宽度，只用来定分列比例。
    //
    // 之前是「Table 直接塞进横向 SingleChildScrollView」：横向滚动给子级的是
    // 无限宽约束，Table 的 FlexColumnWidth 在无界宽度下没有可分配空间，列宽会
    // 塌到只剩单元格 padding。文字被挤成一行一个字，整张参数表变成一根竖条，
    // 右边留一大片空白——帖子里的「乱码 + 巨型空白」就是这么来的。
    final wanted = List<double>.filled(columnCount, 0);
    for (final row in rows) {
      final cells = row.querySelectorAll('td,th');
      for (var i = 0; i < columnCount && i < cells.length; i++) {
        final width = _textWidth(_cleanInline(cells[i].text).trim(), fontSize);
        if (width > wanted[i]) wanted[i] = width;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : 320.0;
          // 列多到手机放不下时才横向滚动；普通两三列的参数表铺满屏宽，
          // 文字正常折行，比让用户左右拖着看舒服。
          final scrollable = columnCount > 5;
          final minColumn = scrollable ? 72.0 : 44.0;
          final columns = [for (final w in wanted) (w + 16).clamp(minColumn, 320.0)];
          final wantedTotal = columns.fold<double>(0, (a, b) => a + b);
          final tableWidth = scrollable ? wantedTotal.clamp(available, 2400.0) : available;
          final columnWidths = <int, TableColumnWidth>{
            for (var i = 0; i < columnCount; i++)
              i: FixedColumnWidth(columns[i] / wantedTotal * tableWidth),
          };

          final body = Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder.all(color: scheme.outlineVariant.withValues(alpha: 0.55), width: 0.7),
            columnWidths: columnWidths,
            children: [
              for (final row in rows)
                TableRow(
                  // 带 <th> 的行当表头：加粗 + 淡底色，和网页端观感接近。
                  decoration: row.querySelector('th') == null
                      ? null
                      : BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.45)),
                  children: [
                    for (var i = 0; i < columnCount; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Text(
                          () {
                            final cells = row.querySelectorAll('td,th');
                            return i < cells.length ? _cleanInline(cells[i].text).trim() : '';
                          }(),
                          style: TextStyle(
                            fontSize: fontSize,
                            height: 1.35,
                            color: scheme.onSurface,
                            fontWeight: row.querySelector('th') == null ? FontWeight.w400 : FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          );

          if (!scrollable || tableWidth <= available + 0.5) return body;
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: body);
        },
      ),
    );
  }

  Widget? _imageBlock(BuildContext context, dom.Element img) {
    final url = _imageUrl(img);
    if (url.isEmpty) return null;
    final index = widget.images.indexOf(url);
    // 正文里常有十几张长截图：加载时先占一屏灰会让人以为正文没出来，
    // 统一给 160 的矮占位；同时按屏幕宽度解码，避免 3768px 原图直接进内存。
    final screen = MediaQuery.sizeOf(context);
    final scale = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (screen.width * scale).round().clamp(320, 1440);
    // 手机截图（1080×2400 这类）按屏宽铺满就有 800 多高，之前外面套死 520，
    // 超出的部分被圆角直接裁掉，长截图只能看见上面一截——「图片显示不全」就是这么来的。
    // 现在上限放到一屏半，并且用 contain：再长的图也整体缩进框里，不裁。
    final maxImageHeight = (screen.height * 1.6).clamp(400.0, 1600.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // 图片解码完成、进度刷新都只脏这一块；否则整楼（几百段文字）会跟着重绘一次。
      child: RepaintBoundary(
        child: GestureDetector(
          onTap: () {
            final images = widget.images.isEmpty ? <String>[url] : widget.images;
            Navigator.of(context).push(noSwipeRoute(
              builder: (_) => ImageViewerPage(images: images, initialIndex: index < 0 ? 0 : index),
            ));
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxImageHeight),
            child: SmartImage(
              url: url,
              width: double.infinity,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.low,
              radius: BorderRadius.circular(12),
              cacheWidth: cacheWidth,
              placeholderHeight: 160,
            ),
          ),
        ),
      ),
    );
  }

  List<InlineSpan> _inlineNode(BuildContext context, dom.Node node, TextStyle style) {
    final spans = <InlineSpan>[];
    if (node is dom.Text) {
      final text = _cleanInline(node.text);
      if (text.isNotEmpty) spans.addAll(_linkifyText(context, text, style));
      return spans;
    }
    if (node is! dom.Element) return spans;

    final tag = node.localName ?? '';
    switch (tag) {
      case 'br':
        spans.add(const TextSpan(text: '\n'));
        return spans;
      case 'b':
      case 'strong':
        return _inlineChildren(context, node, style.copyWith(fontWeight: FontWeight.w700));
      case 'i':
      case 'em':
        return _inlineChildren(context, node, style.copyWith(fontStyle: FontStyle.italic));
      case 'u':
      case 'ins':
        return _inlineChildren(context, node, style.copyWith(decoration: TextDecoration.underline));
      case 's':
      case 'del':
        return _inlineChildren(context, node, style.copyWith(decoration: TextDecoration.lineThrough));
      case 'font':
        final color = _parseColor(node.attributes['color']);
        return _inlineChildren(context, node, color == null ? style : style.copyWith(color: color));
      case 'code':
        return [
          TextSpan(
            text: node.text,
            style: style.copyWith(
              fontFamily: 'monospace',
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ];
      case 'a':
        final href = node.attributes['href'] ?? '';
        if (href.isEmpty || href.startsWith('javascript')) {
          return _inlineChildren(context, node, style);
        }
        final url = AppConfig.uri(href).toString();
        final recognizer = TapGestureRecognizer()..onTap = () => _openLink(context, url);
        _recognizers.add(recognizer);
        return [
          TextSpan(
            text: node.text.isEmpty ? url : node.text,
            style: style.copyWith(color: _linkColor(context), decoration: TextDecoration.underline),
            recognizer: recognizer,
          ),
        ];
      case 'img':
        if (_isSmiley(node)) {
          final src = _imageUrl(node);
          if (src.isNotEmpty) {
            return [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Image.network(src, width: 22, height: 22, headers: _headers(), errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ];
          }
          return const [];
        }
        final image = _imageBlock(context, node);
        if (image == null) return const [];
        return [WidgetSpan(alignment: PlaceholderAlignment.middle, child: image)];
      default:
        return _inlineChildren(context, node, style);
    }
  }

  /// 自动识别正文里服务端没转成 <a> 的地址。
  ///
  /// Discuz 的隐藏内容（[hide] 回复可见）里，用户手打的链接往往是裸文本，
  /// 服务端不会帮忙加 <a>，这里补上：完整 URL、`www.` 开头，以及
  /// `pan.baidu.com/s/xxx` 这种不带协议头的域名都认。
  List<InlineSpan> _linkifyText(BuildContext context, String text, TextStyle style) {
    final spans = <InlineSpan>[];
    // 只吃 ASCII 里的 URL 合法字符：紧跟其后的中文不该被吞进链接。
    const urlChars = r'[A-Za-z0-9\-._~:/?#\[\]@!$&()*+,;=%]';
    // 裸域名靠顶级域白名单兜底，避免把「1.9.1」这类版本号认成网址。
    const tlds = r'com|cn|net|org|cc|io|top|xyz|me|tv|info|biz|vip|club|site|app|dev|'
        r'co|ltd|wang|tech|online|store|fun|live|pro|ink|wiki|link|cloud|plus|'
        r'shop|art|design|blog|page|work|space|world|life|news|mobi|asia|'
        r'tw|hk|jp|kr|us|uk|de|ru';
    final pattern = RegExp(
      '(?:https?://$urlChars+)'
      '|(?:www\\.$urlChars+)'
      '|(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+(?:$tlds)$urlChars*)',
      caseSensitive: false,
    );
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      // user@qq.com 的 qq.com 不是独立链接，前面连着字母数字就直接放过。
      if (match.start > 0 && RegExp(r'[A-Za-z0-9@_\-]').hasMatch(text[match.start - 1])) {
        continue;
      }
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start), style: style));
      }
      var url = match.group(0)!;
      var suffix = '';
      const punctuation = '，。；！？、）》】」』,.;:!?';
      while (url.isNotEmpty && punctuation.contains(url[url.length - 1])) {
        suffix = url[url.length - 1] + suffix;
        url = url.substring(0, url.length - 1);
      }
      if (url.isEmpty) {
        spans.add(TextSpan(text: match.group(0), style: style));
      } else {
        // 裸域名补上协议头再交给路由，否则会被当成站内相对路径。
        final hasScheme = url.startsWith('http://') || url.startsWith('https://');
        final linkUrl = AppConfig.uri(hasScheme ? url : 'https://$url').toString();
        final recognizer = TapGestureRecognizer()..onTap = () => _openLink(context, linkUrl);
        _recognizers.add(recognizer);
        spans.add(TextSpan(
          text: url,
          style: style.copyWith(
            color: _linkColor(context),
            decoration: TextDecoration.underline,
          ),
          recognizer: recognizer,
        ));
        if (suffix.isNotEmpty) spans.add(TextSpan(text: suffix, style: style));
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }
    return spans;
  }

  List<InlineSpan> _inlineChildren(BuildContext context, dom.Element element, TextStyle style) {
    final spans = <InlineSpan>[];
    for (final child in element.nodes) {
      spans.addAll(_inlineNode(context, child, style));
    }
    return spans;
  }

  Future<void> _openLink(BuildContext context, String url) async {
    // 视频链接统一进应用内播放，不再丢给系统浏览器。
    final video = parseVideoLink(url);
    if (video != null) {
      _openVideo(context, video);
      return;
    }

    final target = ForumLink.parse(url);
    if (target is ThreadLink) {
      // 楼层链接常常只带 pid，得先问服务端它属于哪个主题。
      final tid = target.needsLookup ? await _lookupTid(target.pid) : target.tid;
      if (tid > 0) {
        if (!context.mounted) return;
        Navigator.of(context).push(appRoute(
          builder: (_) => ThreadPage(tid: tid, initialPid: target.pid),
        ));
        return;
      }
      // 楼层被删、链接过期时认不出主题号，退回内置浏览器看站点提示。
    } else if (target is BoardLink) {
      Navigator.of(context).push(appRoute(
        builder: (_) => BoardThreadsPage(fid: target.fid, name: '版块'),
      ));
      return;
    } else if (target is UserLink) {
      _openUser(context, target.uid, '');
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri != null && AppConfig.isForumHost(uri.host)) {
      final mod = uri.queryParameters['mod'];
      if (mod == 'post' && uri.queryParameters['action'] == 'reply') {
        widget.onReply?.call();
        return;
      }
    }
    if (!context.mounted) return;
    Navigator.of(context).push(appRoute(builder: (_) => InternalBrowserPage(url: url)));
  }

  /// 只有 pid 的楼层链接要先问服务端这楼属于哪个主题。失败就返回 0，
  /// 由调用方回退到内置浏览器。
  Future<int> _lookupTid(int pid) async {
    if (pid <= 0) return 0;
    try {
      return await AppState.instance.repo.resolveThreadIdByPid(pid);
    } catch (_) {
      return 0;
    }
  }

  Map<String, String> _headers() {
    final cookie = HttpSession.instance.cookieHeader;
    return {
      'Referer': AppConfig.base,
      'User-Agent': AppConfig.userAgent,
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  static final RegExp _hex6 = RegExp(r'^[0-9a-fA-F]{6}$');
  static final RegExp _hex3 = RegExp(r'^[0-9a-fA-F]{3}$');

  /// `<font color>` 的值可能是 `#ff0000`、`Red`、`blue` 这类具名色。
  /// 早先把「长度 3」直接当三位十六进制扩展，`Red` 会被拼成 `RReedd`，
  /// 再进 `int.parse(radix: 16)` 抛异常，整楼正文随之中断渲染（长帖变空白）。
  /// 这里先按十六进制严格校验，不匹配才走具名色，最后兜底为 null。
  Color? _parseColor(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;
    final hex = raw.replaceFirst('#', '');
    if (_hex6.hasMatch(hex)) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    if (_hex3.hasMatch(hex)) {
      final expanded = hex.split('').map((e) => '$e$e').join();
      return Color(int.parse('FF$expanded', radix: 16));
    }
    return switch (raw.toLowerCase()) {
      'red' => Colors.red,
      'blue' => Colors.blue,
      'green' => Colors.green,
      'gray' || 'grey' => Colors.grey,
      'orange' => Colors.orange,
      'yellow' => Colors.yellow,
      'purple' => Colors.purple,
      'pink' => Colors.pink,
      'white' => Colors.white,
      'black' => Colors.black,
      _ => null,
    };
  }

  String _cleanInline(String text) => text
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD]'), '')
      .replaceAll(RegExp(r'[ \t\r\n]+'), ' ');

  @override
  Widget build(BuildContext context) {
    var cache = _cache;
    if (cache == null) {
      try {
        cache = _blocks(context, parser.parseFragment(widget.html).nodes);
      } catch (error) {
        // 楼层 HTML 千奇百怪，渲染偶尔会踩到没预料到的标签组合。
        // 不能让一处异常把整楼吞成空白：退回纯文本，至少内容读得到。
        debugPrint('PostHtmlView 渲染失败，降级为纯文本：$error');
        final text = parser.parseFragment(widget.html).text?.trim() ?? '';
        cache = <Widget>[
          if (text.isNotEmpty)
            Text(
              text,
              style: TextStyle(
                fontSize: 15.5,
                height: 1.62,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
        ];
      }
      _cache = cache;
    }
    if (cache.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Text('该楼层暂无内容', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant));
    }
    final chunks = _chunks ??= _split(cache);
    final visible = <Widget>[];
    for (var i = 0; i < _visibleChunks && i < chunks.length; i++) {
      visible.addAll(chunks[i]);
    }
    if (_visibleChunks < chunks.length) _scheduleNextChunk();
    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: visible);
    return widget.selectable ? SelectionArea(child: content) : content;
  }
}

/// 楼层里的引用块，按网页端 .quote 的样子呈现：
/// 左侧一条灰竖线、浅灰底，头部「作者 发表于 时间」，正文完整显示。
class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.author,
    required this.time,
    required this.body,
    this.onTapAuthor,
  });

  final String author;
  final String time;
  final String body;
  final VoidCallback? onTapAuthor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final headStyle = TextStyle(fontSize: 12.5, height: 1.5, color: scheme.onSurfaceVariant);
    final hasHead = author.isNotEmpty || time.isNotEmpty;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2, bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border(left: BorderSide(color: scheme.outlineVariant, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasHead)
            Text.rich(
              TextSpan(
                children: [
                  if (author.isNotEmpty)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: onTapAuthor,
                        child: Text(
                          author,
                          style: headStyle.copyWith(
                            color: onTapAuthor == null ? null : scheme.primary,
                          ),
                        ),
                      ),
                    ),
                  if (author.isNotEmpty && time.isNotEmpty)
                    TextSpan(text: ' 发表于 ', style: headStyle),
                  if (time.isNotEmpty) TextSpan(text: time, style: headStyle),
                ],
              ),
            ),
          if (hasHead && body.isNotEmpty) const SizedBox(height: 4),
          if (body.isNotEmpty)
            Text(
              body,
              style: TextStyle(fontSize: 14, height: 1.66, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
