import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../../core/pending_upload.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/emoji_panel.dart';
import '../widgets/board_picker_sheet.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_controls.dart';
import '../widgets/measure_height.dart';
import '../widgets/thread_glass.dart';
import 'login_page.dart';
import '../navigation/app_routes.dart';

/// 发布新主题：标题 / 正文 / 表情 / 图片 / @ / 插入 / 附件 / 高级选项 / 草稿。
class ComposePage extends StatefulWidget {
  const ComposePage({super.key, this.initialFid, this.initialBoardName});

  final int? initialFid;
  final String? initialBoardName;

  @override
  State<ComposePage> createState() => _ComposePageState();
}

enum _ComposePanel { emoji, mention, insert, attach, advanced }

class _DraftAttachment {
  _DraftAttachment({
    required this.name,
    required this.bytes,
    required this.image,
  });

  final String name;
  final Uint8List bytes;
  final bool image;
  int? aid;
  bool uploading = false;
  String? error;

  /// 站点模板拿不到 swfupload 凭证，改成跟着发帖请求一起提交。
  bool pending = false;
}

class _ComposePageState extends State<ComposePage> {
  static const String _draftSubject = 'mt_compose_draft_subject';
  static const String _draftMessage = 'mt_compose_draft_message';
  static const String _draftFidKey = 'mt_compose_draft_fid';
  static const String _draftAt = 'mt_compose_draft_at';

  final TextEditingController _subject = TextEditingController();
  final TextEditingController _tags = TextEditingController();
  final TextEditingController _message = TextEditingController();
  final TextEditingController _mention = TextEditingController();
  final TextEditingController _linkUrl = TextEditingController();
  final TextEditingController _linkText = TextEditingController();
  final TextEditingController _mediaUrl = TextEditingController();
  final FocusNode _messageFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _messageKey = GlobalKey();
  final ImagePicker _picker = ImagePicker();
  final List<_DraftAttachment> _attachments = <_DraftAttachment>[];
  final List<TextEditingController> _pollOptions = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];

  List<ForumCategory> _categories = const [];
  bool _loadingBoards = true;
  bool _submitting = false;
  bool _uploading = false;
  bool _restoredDraft = false;
  bool _poll = false;
  bool _pollMultiple = false;
  int? _fid;
  int? _draftFid;
  String? _error;
  ComposeInfo? _info;
  _ComposePanel? _panel;
  String? _insertKind;
  List<FriendItem> _mentionFriends = const <FriendItem>[];
  bool _mentionFriendsLoading = false;
  String? _mentionFriendsError;

  bool _replyOnly = false;
  bool _orderDesc = false;
  bool _notify = true;
  bool _useSignature = true;

  final TextEditingController _readPerm = TextEditingController();
  final TextEditingController _price = TextEditingController();

  @override
  void initState() {
    super.initState();
    _messageFocus.addListener(_onMessageFocus);
    _init();
  }

  @override
  void dispose() {
    _subject.dispose();
    _tags.dispose();
    _message.dispose();
    _mention.dispose();
    _linkUrl.dispose();
    _linkText.dispose();
    _mediaUrl.dispose();
    _readPerm.dispose();
    _price.dispose();
    _messageFocus.dispose();
    _scroll.dispose();
    for (final controller in _pollOptions) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    await _restoreDraft();
    await _loadBoards();
    if (mounted && _restoredDraft) {
      _toast('已恢复上次保存的草稿');
    }
  }

  Future<void> _restoreDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final subject = prefs.getString(_draftSubject) ?? '';
    final message = prefs.getString(_draftMessage) ?? '';
    if (subject.trim().isEmpty && message.trim().isEmpty) return;
    final savedAt = prefs.getInt(_draftAt) ?? 0;
    if (savedAt > 0 &&
        DateTime.now().millisecondsSinceEpoch - savedAt >
            7 * 24 * 3600 * 1000) {
      return;
    }
    _subject.text = subject;
    _message.text = message;
    _draftFid = prefs.getInt(_draftFidKey);
    _restoredDraft = true;
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftSubject, _subject.text);
    await prefs.setString(_draftMessage, _message.text);
    await prefs.setInt(_draftAt, DateTime.now().millisecondsSinceEpoch);
    final fid = _fid;
    if (fid != null) await prefs.setInt(_draftFidKey, fid);
    _toast('草稿已保存，下次进入发帖页会自动恢复');
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftSubject);
    await prefs.remove(_draftMessage);
    await prefs.remove(_draftFidKey);
    await prefs.remove(_draftAt);
  }

  Future<void> _loadBoards() async {
    try {
      final value = await AppState.instance.boards();
      if (!mounted) return;
      var fid = _fid ?? _draftFid ?? widget.initialFid;
      final exists =
          fid != null && value.any((c) => c.boards.any((b) => b.fid == fid));
      if (!exists) {
        fid = value.isNotEmpty && value.first.boards.isNotEmpty
            ? value.first.boards.first.fid
            : null;
      }
      setState(() {
        _categories = value;
        _fid = fid;
        _loadingBoards = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBoards = false;
        _error = _messageOf(e);
      });
    }
  }

  List<(String, int)> get _options {
    final options = <(String, int)>[];
    for (final category in _categories) {
      for (final board in category.boards) {
        options.add(('${category.name} / ${board.name}', board.fid));
      }
    }
    return options;
  }

  String _messageOf(Object error) =>
      error is SiteException ? error.message : '操作失败，请稍后重试';

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _ensureLogin() async {
    if (AppState.instance.isLoggedIn) return true;
    final ok = await Navigator.of(context)
        .push<bool>(noSwipeRoute(builder: (_) => const LoginPage()));
    return ok == true && AppState.instance.isLoggedIn;
  }

  Future<ComposeInfo?> _ensureInfo() async {
    final cached = _info;
    if (cached != null && cached.formhash.isNotEmpty) return cached;
    final fid = _fid;
    if (fid == null) {
      setState(() => _error = '请选择要发布的版块');
      return null;
    }
    if (!await _ensureLogin()) return null;
    if (!mounted) return null;
    try {
      final value = await AppState.instance.repo.fetchComposeInfo(fid);
      if (!mounted) return null;
      setState(() => _info = value);
      return value;
    } catch (e) {
      if (!mounted) return null;
      setState(() => _error = _messageOf(e));
      _toast(_messageOf(e));
      return null;
    }
  }

  /// 忽略缓存重新拉发帖页，专治「上一秒还没拿到 hash」。
  Future<ComposeInfo?> _refreshInfo() async {
    final fid = _fid;
    if (fid == null) return null;
    try {
      final value = await AppState.instance.repo.fetchComposeInfo(fid);
      if (mounted) setState(() => _info = value);
      return value;
    } catch (_) {
      return null;
    }
  }

  /// 当前所选版块的展示名（含分区），没选时为空。
  String? get _boardLabel {
    final fid = _fid;
    if (fid == null) return null;
    for (final category in _categories) {
      for (final board in category.boards) {
        if (board.fid == fid) return '${category.name} / ${board.name}';
      }
    }
    return null;
  }

  Future<void> _openBoardPicker() async {
    if (_categories.isEmpty) {
      _toast('版块列表还没加载好，稍后再试');
      return;
    }
    final picked = await BoardPickerSheet.show(
      context,
      categories: _categories,
      selected: _fid ?? 0,
      showAll: false,
    );
    if (!mounted || picked == null || picked == _fid) return;
    setState(() {
      _fid = picked;
      _info = null;
    });
  }

  void _onMessageFocus() {
    if (!_messageFocus.hasFocus) return;
    if (_panel != null) {
      setState(() => _panel = null);
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _ensureMessageVisible(),
    );
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (mounted) _ensureMessageVisible();
    });
  }

  /// 键盘弹出后把正文输入框滚动到可见区域，避免被输入法遮挡。
  void _ensureMessageVisible() {
    final ctx = _messageKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 220),
      alignment: 0.35,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  void _togglePanel(_ComposePanel panel) {
    FocusScope.of(context).unfocus();
    final openingMention = panel == _ComposePanel.mention && _panel != panel;
    setState(() {
      _panel = _panel == panel ? null : panel;
      if (_panel != _ComposePanel.insert) _insertKind = null;
    });
    if (openingMention) _loadMentionFriends();
  }

  Future<void> _loadMentionFriends({bool force = false}) async {
    if (_mentionFriendsLoading) return;
    if (!AppState.instance.isLoggedIn) {
      if (mounted) setState(() => _mentionFriendsError = '登录后可读取论坛好友列表');
      return;
    }
    if (!force && _mentionFriends.isNotEmpty) return;
    setState(() {
      _mentionFriendsLoading = true;
      _mentionFriendsError = null;
    });
    try {
      final friends = await AppState.instance.repo.fetchFriends();
      if (!mounted) return;
      setState(() {
        _mentionFriends = friends;
        _mentionFriendsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _mentionFriendsError = _messageOf(e));
    } finally {
      if (mounted) setState(() => _mentionFriendsLoading = false);
    }
  }

  Future<void> _pickImages() async {
    final info = await _ensureInfo();
    if (info == null) return;
    final picked = await _picker.pickMultiImage(
      maxWidth: 1600,
      imageQuality: 78,
    );
    if (picked.isEmpty) return;
    if (!mounted) return;
    for (final file in picked) {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final attachment = _DraftAttachment(
        name: file.name,
        bytes: bytes,
        image: true,
      );
      setState(() => _attachments.add(attachment));
      await _upload(attachment, image: true);
    }
  }

  Future<void> _pickFiles() async {
    final info = await _ensureInfo();
    if (info == null) return;
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return;
    if (!mounted) return;
    for (final file in files) {
      final Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (_) {
        _toast('${file.name} 读取失败');
        continue;
      }
      if (!mounted) return;
      final attachment = _DraftAttachment(
        name: file.name,
        bytes: bytes,
        image: false,
      );
      setState(() => _attachments.add(attachment));
      await _upload(attachment, image: false);
    }
  }

  Future<void> _upload(
    _DraftAttachment attachment, {
    required bool image,
  }) async {
    var info = _info;
    final fid = _fid;
    if (fid == null) return;
    // 页面里没解析到凭证、或者 uid 是 0 时，重新拉一次发帖页再试，
    // 而不是直接让用户看着「凭证已失效」发懵。
    if (info == null || info.uploadHash.isEmpty || info.uid <= 0) {
      info = await _refreshInfo();
    }
    if (info == null) {
      setState(() {
        attachment.uploading = false;
        attachment.error = '发帖页打不开，稍后再试';
      });
      _toast('发帖页打不开，稍后再试');
      return;
    }
    if (info.uploadHash.isEmpty || info.uid <= 0) {
      // 这套模板的页面上没有 swfupload 的 hash（它由站点私钥算出来，客户端
      // 推不出来），只能学网页的做法：把文件放进发帖表单一起提交。
      setState(() {
        attachment.uploading = false;
        attachment.error = null;
        attachment.pending = true;
      });
      _toast('图片会跟着帖子一起提交，发帖后出现在文末');
      return;
    }
    setState(() {
      attachment.uploading = true;
      attachment.error = null;
      attachment.pending = false;
      _uploading = true;
    });
    try {
      final aid = await AppState.instance.repo.uploadAttachment(
        bytes: attachment.bytes,
        filename: attachment.name,
        uploadHash: info.uploadHash,
        uid: info.uid,
        fid: fid,
        referer: AppConfig.uri('forum.php', {
          'mod': 'post',
          'action': 'newthread',
          'fid': '$fid',
          'mobile': '2',
        }).toString(),
        image: image,
      );
      if (!mounted) return;
      attachment.aid = aid;
      insertAtCursor(
        _message,
        image ? '\n[attachimg]$aid[/attachimg]\n' : '\n[attach]$aid[/attach]\n',
      );
      setState(() => attachment.uploading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        attachment.uploading = false;
        attachment.error = _messageOf(e);
      });
      _toast(_messageOf(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _removeAttachment(_DraftAttachment attachment) {
    final aid = attachment.aid;
    if (aid != null) {
      final tag = attachment.image
          ? '[attachimg]$aid[/attachimg]'
          : '[attach]$aid[/attach]';
      _message.text = _message.text.replaceAll(tag, '');
    }
    setState(() => _attachments.remove(attachment));
  }

  void _insertMention([String? selectedUsername]) {
    final name = (selectedUsername ?? _mention.text).trim();
    if (name.isEmpty) {
      _toast('请输入要 @ 的用户名');
      return;
    }
    insertAtCursor(_message, '@$name ');
    _mention.clear();
    setState(() => _panel = null);
    _messageFocus.requestFocus();
  }

  void _insertLink() {
    final url = _linkUrl.text.trim();
    if (url.isEmpty) {
      _toast('请输入链接网址');
      return;
    }
    final text = _linkText.text.trim().isEmpty ? url : _linkText.text.trim();
    insertAtCursor(_message, '[url=$url]$text[/url]');
    _linkUrl.clear();
    _linkText.clear();
    _insertKind = null;
    setState(() => _panel = null);
    _messageFocus.requestFocus();
  }

  void _insertMedia(String kind) {
    final url = _mediaUrl.text.trim();
    if (url.isEmpty) {
      _toast('请输入链接地址');
      return;
    }
    final code = switch (kind) {
      'image' => '[img]$url[/img]',
      'audio' => '[audio]$url[/audio]',
      'video' => '[media=x,500,375]$url[/media]',
      'flash' => '[flash=480,400]$url[/flash]',
      _ => url,
    };
    insertAtCursor(_message, code);
    _mediaUrl.clear();
    _insertKind = null;
    setState(() => _panel = null);
    _messageFocus.requestFocus();
  }

  void _insertWrap(String tag) {
    insertWrapped(_message, '[$tag]', '[/$tag]');
    setState(() => _panel = null);
    _messageFocus.requestFocus();
  }

  void _addPollOption() {
    if (_pollOptions.length >= 10) {
      _toast('最多添加 10 个选项');
      return;
    }
    setState(() => _pollOptions.add(TextEditingController()));
  }

  void _removePollOption(int index) {
    if (_pollOptions.length <= 2) return;
    final controller = _pollOptions.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  List<String> get _pollTexts => [
    for (final controller in _pollOptions)
      if (controller.text.trim().isNotEmpty) controller.text.trim(),
  ];

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    setState(() => _panel = null);
    final fid = _fid;
    final subject = _subject.text.trim();
    final message = _message.text.trim();
    if (fid == null) {
      setState(() => _error = '请选择要发布的版块');
      return;
    }
    if (subject.isEmpty) {
      setState(() => _error = '请填写标题');
      return;
    }
    final options = _pollTexts;
    if (_poll && options.length < 2) {
      setState(() => _error = '投票至少需要两个选项');
      return;
    }
    if (!_poll && message.length < 4) {
      setState(() => _error = '正文内容太短');
      return;
    }
    final info = await _ensureInfo();
    if (info == null) return;
    if (!mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await AppState.instance.repo.createThread(
        fid: fid,
        subject: subject,
        message: message,
        formhash: info.formhash,
        attachmentIds: [
          for (final attachment in _attachments)
            if (attachment.aid != null) attachment.aid!,
        ],
        // 拿不到 swfupload 凭证的那些图，跟着这次提交一起送上去。
        pendingFiles: [
          for (final attachment in _attachments)
            if (attachment.pending)
              PendingUpload(
                filename: attachment.name,
                bytes: attachment.bytes,
                image: attachment.image,
              ),
        ],
        replyOnly: _replyOnly,
        orderDesc: _orderDesc,
        notify: _notify,
        useSignature: _useSignature,
        readPerm: _readPerm.text.trim(),
        price: _price.text.trim(),
        poll: _poll,
        pollOptions: options,
        pollMultiple: _pollMultiple,
        tags: _tags.text.trim(),
      );
      await _clearDraft();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result)));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _messageOf(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      // 自行处理键盘高度，保证底部输入区始终浮在输入法之上。
      resizeToAvoidBottomInset: false,
      // 正文从玻璃顶栏背后滚过。
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Text(
          widget.initialBoardName == null
              ? '发帖'
              : '发帖 · ${widget.initialBoardName}',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _publishButton(scheme),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            // 编辑区铺满 body，正文从底部工具条背后掠过。
            // 让位高度加在 ListView 的 padding 上：加在外层会把视口截短，
            // 工具条背后只剩纯色底，玻璃就白做了。
            Positioned.fill(
              child: ListView(
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  16,
                  glassTopInset(context) + 12,
                  16,
                  _bottomBarHeight + insets + 16,
                ),
                children: _content(scheme),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: insets,
              child: MeasureHeight(
                onHeight: _onBottomBarMeasured,
                child: _bottomBar(scheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部工具条（含展开的面板）给正文让出的高度。
  ///
  /// 面板高度由内容决定，估不准；交给 [MeasureHeight] 量，首帧先给个估值。
  double _bottomBarHeight = 58;

  void _onBottomBarMeasured(double height) {
    if ((height - _bottomBarHeight).abs() < 0.5) return;
    setState(() => _bottomBarHeight = height);
  }

  /// 顶栏右上角的发布按钮。
  ///
  /// 原来是 AppBar actions 里的 TextButton，动作区被压到只剩二十来像素，
  /// 「发布」两个字被折成两行。改成一个宽度随内容的主色胶囊，既不会被挤，
  /// 也和页面里的玻璃控件对得上。
  Widget _publishButton(ColorScheme scheme) {
    final busy = _submitting;
    return Opacity(
      opacity: busy ? 0.6 : 1,
      child: Material(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : _submit,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                else
                  const Icon(Icons.send_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 5),
                Text(
                  busy ? '发布中' : '发布',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(ColorScheme scheme) {
    return GlassBackdrop(
      showBorder: false,
      opacityScale: 0.94,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: ThreadGlass.borderColor(context), width: 0.6),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [_toolbar(scheme), _panelArea()],
        ),
      ),
    );
  }

  List<Widget> _content(ColorScheme scheme) {
    return [
      _modeTabs(),
      const SizedBox(height: 12),
      if (_loadingBoards)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        )
      else if (_options.isNotEmpty)
        GlassSelectRow(
          label: '发布到',
          value: _boardLabel,
          placeholder: '选择一个版块',
          leading: Icons.dashboard_outlined,
          onTap: _openBoardPicker,
        ),
      const SizedBox(height: 14),
      GlassField(
        controller: _subject,
        label: '标题',
        hintText: '一句话说明你的主题',
        leading: Icons.title_rounded,
        maxLength: 80,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 14),
      GlassField(
        controller: _tags,
        label: '主题标签（可选）',
        hintText: '多个标签用空格分隔',
        leading: Icons.sell_outlined,
        maxLength: 60,
      ),
      const SizedBox(height: 14),
      if (_poll) ...[_pollEditor(scheme), const SizedBox(height: 14)],
      KeyedSubtree(
        key: _messageKey,
        child: GlassField(
          controller: _message,
          focusNode: _messageFocus,
          minLines: _poll ? 3 : 8,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          hintText: _poll
              ? '投票说明（可选）'
              : '想和大家分享点什么…\n\n支持 Discuz 常用 BBCode，可在下方工具栏插入表情、图片与链接。',
        ),
      ),
      if (_attachments.isNotEmpty) ...[
        const SizedBox(height: 14),
        _attachmentGrid(scheme),
      ],
      if (_error != null) ...[
        const SizedBox(height: 14),
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
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            flex: 3,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _submitting ? '正在发布…' : '发表',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: GlassCard(
              radius: 14,
              onTap: _submitting ? null : _saveDraft,
              child: SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.save_outlined, size: 17, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      '草稿',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Text(
        '请遵守 MT论坛版规，发布前确认内容与所选版块相符。',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: scheme.outline),
      ),
    ];
  }

  /// 帖子 / 投票的切换。
  Widget _modeTabs() {
    return GlassSegmented<bool>(
      segments: const [(false, '发表帖子'), (true, '发投票')],
      value: _poll,
      expand: true,
      onChanged: (value) => setState(() => _poll = value),
    );
  }

  Widget _pollEditor(ColorScheme scheme) {
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.how_to_vote_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '投票选项',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${_pollOptions.length}/10',
                style: TextStyle(fontSize: 11.5, color: scheme.outline),
              ),
            ],
          ),
          for (var i = 0; i < _pollOptions.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: GlassField(
                      controller: _pollOptions[i],
                      hintText: '选项 ${i + 1}',
                      maxLength: 40,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  if (_pollOptions.length > 2)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '删除选项',
                      onPressed: () => _removePollOption(i),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: _addPollOption,
            // 默认的水平 padding 让「+ 添加选项」比选项框缩进一大截，
            // 压平后和上面的输入框左边缘对齐。
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('添加选项'),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('允许多选', style: TextStyle(fontSize: 13.5)),
            value: _pollMultiple,
            onChanged: (value) => setState(() => _pollMultiple = value),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '至少填写 2 个选项，提交后生成投票主题。',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentGrid(ColorScheme scheme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final attachment in _attachments) _thumb(attachment, scheme),
        _addTile(scheme),
      ],
    );
  }

  Widget _thumb(_DraftAttachment attachment, ColorScheme scheme) {
    return SizedBox(
      width: 78,
      height: 78,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: attachment.image
                  ? Image.memory(
                      attachment.bytes,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _fileTile(scheme, Icons.broken_image_outlined),
                    )
                  : _fileTile(scheme, Icons.insert_drive_file_outlined),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
              ),
            ),
          ),
          if (attachment.uploading)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          if (attachment.error != null)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(
                    Icons.error_outline_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          if (attachment.pending)
            Positioned(
              left: 2,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '随帖上传',
                  style: TextStyle(fontSize: 8.5, color: Colors.white),
                ),
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: attachment.uploading
                  ? null
                  : () => _removeAttachment(attachment),
              child: const CircleAvatar(
                radius: 9,
                backgroundColor: Colors.black54,
                child: Icon(Icons.close_rounded, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileTile(ColorScheme scheme, IconData icon) {
    return Container(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: Icon(icon, color: scheme.onSurfaceVariant, size: 26),
    );
  }

  Widget _addTile(ColorScheme scheme) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _uploading ? null : _pickImages,
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(
          Icons.add_rounded,
          color: scheme.onSurfaceVariant,
          size: 30,
        ),
      ),
    );
  }

  Widget _toolbar(ColorScheme scheme) {
    const items = <(_ComposePanel, IconData, String)>[
      (_ComposePanel.emoji, Icons.sentiment_satisfied_alt_rounded, '表情'),
      (_ComposePanel.mention, Icons.alternate_email_rounded, '@朋友'),
      (_ComposePanel.insert, Icons.send_rounded, '插入'),
      (_ComposePanel.attach, Icons.attach_file_rounded, '附件'),
      (_ComposePanel.advanced, Icons.tune_rounded, '高级'),
    ];
    return Row(
      children: [
        for (final item in items)
          Expanded(
            child: InkWell(
              onTap: () => _togglePanel(item.$1),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.$2,
                      size: 21,
                      color: _panel == item.$1
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.$3,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: _panel == item.$1
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _panelArea() {
    return switch (_panel) {
      _ComposePanel.emoji => EmojiPanel(
        onSelected: (emoji) => insertAtCursor(_message, emoji),
      ),
      _ComposePanel.mention => _mentionPanel(),
      _ComposePanel.insert => _insertPanel(),
      _ComposePanel.attach => _attachPanel(),
      _ComposePanel.advanced => _advancedPanel(),
      null => const SizedBox.shrink(),
    };
  }

  Widget _panelShell(Widget child) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      // 面板底板交给外层那块玻璃，这里再铺一层实色就把模糊挡住了。
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: child,
      ),
    );
  }

  Widget _mentionPanel() {
    final scheme = Theme.of(context).colorScheme;
    final keyword = _mention.text.trim().toLowerCase();
    final visibleFriends = _mentionFriends
        .where(
          (friend) =>
              keyword.isEmpty ||
              friend.username.toLowerCase().contains(keyword),
        )
        .take(12)
        .toList();
    return _panelShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GlassField(
                  controller: _mention,
                  hintText: '搜索好友或输入用户名',
                  leading: Icons.search_rounded,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _insertMention(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _insertMention, child: const Text('@添加')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '选择好友可快速插入 @用户名；也可以手动输入。',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (AppState.instance.isLoggedIn)
                IconButton(
                  tooltip: '刷新好友',
                  visualDensity: VisualDensity.compact,
                  onPressed: _mentionFriendsLoading
                      ? null
                      : () => _loadMentionFriends(force: true),
                  icon: const Icon(Icons.refresh, size: 18),
                )
              else
                TextButton(
                  onPressed: () async {
                    final ok = await _ensureLogin();
                    if (ok && mounted) _loadMentionFriends(force: true);
                  },
                  child: const Text('登录'),
                ),
            ],
          ),
          if (_mentionFriendsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_mentionFriendsError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _mentionFriendsError!,
                      style: TextStyle(fontSize: 12, color: scheme.error),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _loadMentionFriends(force: true),
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          else if (visibleFriends.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                _mentionFriends.isEmpty
                    ? '暂未读取到好友；可直接输入用户名后点击「@添加」。'
                    : '没有匹配的好友；仍可直接 @ 添加。',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            )
          else
            ...visibleFriends.map((friend) {
              final avatar = friend.avatar.trim();
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 17,
                  backgroundColor: scheme.surfaceContainerHighest,
                  child: avatar.isEmpty
                      ? Icon(
                          Icons.person_outline,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        )
                      : ClipOval(
                          child: Image.network(
                            avatar.startsWith('//') ? 'https:$avatar' : avatar,
                            width: 34,
                            height: 34,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.person_outline,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                ),
                title: Text(
                  friend.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: friend.note.isEmpty
                    ? null
                    : Text(
                        friend.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: const Icon(Icons.alternate_email, size: 18),
                onTap: () => _insertMention(friend.username),
              );
            }),
        ],
      ),
    );
  }

  Widget _insertPanel() {
    final scheme = Theme.of(context).colorScheme;
    const chips = <(String, String, String)>[
      ('link', '文字链接', 'url'),
      ('image', '网络图片', 'img'),
      ('audio', 'MP3 音乐', 'audio'),
      ('video', '网络视频', 'video'),
      ('flash', 'Flash', 'flash'),
      ('quote', '引用', 'quote'),
      ('code', '代码', 'code'),
      ('free', '免费信息', 'free'),
      ('hide', '隐藏内容', 'hide'),
    ];
    return _panelShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final chip in chips)
                ChoiceChip(
                  label: Text(
                    chip.$2,
                    style: TextStyle(
                      fontSize: 12,
                      color: _insertKind == chip.$1
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                  backgroundColor: scheme.surfaceContainerLow,
                  selectedColor: scheme.primaryContainer,
                  side: BorderSide(
                    color: _insertKind == chip.$1
                        ? scheme.primary.withValues(alpha: 0.55)
                        : scheme.outlineVariant.withValues(alpha: 0.75),
                  ),
                  selected: _insertKind == chip.$1,
                  onSelected: (_) {
                    if (chip.$3 != 'url' &&
                        chip.$3 != 'img' &&
                        chip.$3 != 'audio' &&
                        chip.$3 != 'video' &&
                        chip.$3 != 'flash') {
                      _insertWrap(chip.$3);
                      return;
                    }
                    setState(() {
                      _insertKind = chip.$1;
                      _mediaUrl.clear();
                    });
                  },
                ),
            ],
          ),
          if (_insertKind == 'link') ...[
            const SizedBox(height: 12),
            GlassField(
              controller: _linkUrl,
              hintText: '链接网址',
              leading: Icons.link_rounded,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 10),
            GlassField(
              controller: _linkText,
              hintText: '链接文字（可留空）',
              leading: Icons.title_rounded,
            ),
            const SizedBox(height: 10),
            FilledButton(onPressed: _insertLink, child: const Text('插入')),
          ] else if (_insertKind != null) ...[
            const SizedBox(height: 12),
            GlassField(
              controller: _mediaUrl,
              hintText: '链接地址',
              leading: Icons.link_rounded,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => _insertMedia(_insertKind!),
              child: const Text('插入'),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '插入的内容会以 BBCode 追加到正文光标处。',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _attachPanel() {
    final scheme = Theme.of(context).colorScheme;
    return _panelShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _uploading ? null : _pickFiles,
              icon: const Icon(Icons.add_to_drive_rounded),
              label: Text(_uploading ? '正在上传附件…' : '添加文件 / 选择附件'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '可多选文件。具体格式和大小限制由 MT 论坛服务器的附件规则决定；'
            '如果格式不受支持或超过限制，会显示服务器返回的错误原因。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (_attachments.where((item) => !item.image).isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final attachment in _attachments.where((item) => !item.image))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  attachment.error != null
                      ? Icons.error_outline_rounded
                      : attachment.uploading
                      ? Icons.cloud_upload_outlined
                      : Icons.insert_drive_file_outlined,
                  color: attachment.error != null
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
                title: Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: attachment.error == null
                    ? Text(
                        attachment.uploading
                            ? '上传中…'
                            : attachment.aid != null
                            ? '上传完成'
                            : attachment.pending
                            ? '会随帖子一起提交'
                            : '等待上传',
                      )
                    : Text(
                        attachment.error!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.error),
                      ),
                trailing: IconButton(
                  tooltip: '移除附件',
                  onPressed: attachment.uploading
                      ? null
                      : () => _removeAttachment(attachment),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _advancedPanel() {
    return _panelShell(
      Column(
        children: [
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('回帖仅作者可见', style: TextStyle(fontSize: 13.5)),
            value: _replyOnly,
            onChanged: (value) => setState(() => _replyOnly = value),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('回帖倒序排列', style: TextStyle(fontSize: 13.5)),
            value: _orderDesc,
            onChanged: (value) => setState(() => _orderDesc = value),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('接收回复通知', style: TextStyle(fontSize: 13.5)),
            value: _notify,
            onChanged: (value) => setState(() => _notify = value),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('使用个人签名', style: TextStyle(fontSize: 13.5)),
            value: _useSignature,
            onChanged: (value) => setState(() => _useSignature = value),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: GlassField(
                    controller: _readPerm,
                    label: '阅读权限',
                    hintText: '0 为不限制',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GlassField(
                    controller: _price,
                    label: '售价（金币）',
                    hintText: '0 为免费',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
