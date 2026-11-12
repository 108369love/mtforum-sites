import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_controls.dart';
import '../widgets/site_form_dialog.dart';
import '../widgets/smart_image.dart';
import '../widgets/state_views.dart';
import '../widgets/glass_dialog.dart';

/// 道具中心：商店 / 我的道具 / 记录，全部原生实现。
class MagicPage extends StatelessWidget {
  const MagicPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          title: const Text('道具中心'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '商店'),
              Tab(text: '我的道具'),
              Tab(text: '记录'),
            ],
          ),
        ),
        body: const SafeArea(
          top: false,
          child: TabBarView(
            children: [
              _MagicShopTab(),
              _MagicBoxTab(),
              _MagicLogTab(),
            ],
          ),
        ),
      ),
    );
  }
}

String _errorText(Object error, String fallback) =>
    error is SiteException ? error.message : fallback;

Widget _sectionTitle(ColorScheme scheme, String title, [String trailing = '']) {
  return Row(
    children: [
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
      if (trailing.isNotEmpty) ...[
        const SizedBox(width: 8),
        Text(trailing, style: TextStyle(fontSize: 11, color: scheme.outline)),
      ],
    ],
  );
}

/// 道具中心通用卡片：统一走玻璃底 + 描边，和其它页面的卡片刻度一致。
Widget _card(ColorScheme scheme, Widget child) {
  return GlassCard(
    radius: 16,
    padding: const EdgeInsets.all(12),
    child: child,
  );
}

// ---------------------------------------------------------------------------
// 商店
// ---------------------------------------------------------------------------

class _MagicShopTab extends StatefulWidget {
  const _MagicShopTab();

  @override
  State<_MagicShopTab> createState() => _MagicShopTabState();
}

class _MagicShopTabState extends State<_MagicShopTab> with AutomaticKeepAliveClientMixin {
  List<MagicItem> _items = [];
  bool _loading = true;
  bool _busy = false;
  bool _hot = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AppState.instance.repo.fetchMagicShop(hot: _hot);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(e, '加载失败，请稍后重试');
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _buy(MagicItem item) async {
    final request = await showGlassDialog<_MagicActionRequest>(
      context: context,
      builder: (_) => _MagicActionDialog(
        title: '购买 ${item.name}',
        confirmText: '确认购买',
        description: item.priceText.isEmpty ? '' : '价格：${item.priceText}',
      ),
    );
    if (request == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final message = await AppState.instance.repo.buyMagic(mid: item.mid, num: request.num);
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_errorText(e, '购买失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _gift(MagicItem item) async {
    final request = await showGlassDialog<_MagicActionRequest>(
      context: context,
      builder: (_) => _MagicActionDialog(
        title: '赠送 ${item.name}',
        confirmText: '确认赠送',
        needUser: true,
        needMessage: true,
        description: item.priceText.isEmpty ? '' : '购买后直接赠送给对方，价格：${item.priceText}',
      ),
    );
    if (request == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final message = await AppState.instance.repo.giftMagicFromShop(
        mid: item.mid,
        username: request.username,
        num: request.num,
        message: request.message,
      );
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_errorText(e, '赠送失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    if (_loading) return SkeletonView(kind: SkeletonKind.row, topInset: glassTopInset(context));
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: glassPagePadding(context, top: 12, appBarBottom: kTextTabBarHeight),
        children: [
          Row(
            children: [
              _sectionTitle(scheme, '道具商店', '${_items.length} 件'),
              const Spacer(),
              GlassSegmented<bool>(
                segments: const [(false, '全部'), (true, '热销')],
                value: _hot,
                dense: true,
                onChanged: (value) {
                  setState(() => _hot = value);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_items.isEmpty)
            const EmptyView(text: '道具商店暂未开放', icon: Icons.auto_fix_high_outlined)
          else
            for (final item in _items) ...[
              _card(
                scheme,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SmartImage(
                          url: item.image,
                          width: 44,
                          height: 44,
                          radius: BorderRadius.circular(10),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                              ),
                              if (item.priceText.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  item.priceText,
                                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                                ),
                              ],
                              if (item.saleVolume.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  item.saleVolume,
                                  style: TextStyle(fontSize: 10.5, color: scheme.outline),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, height: 1.45, color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (item.soldOut)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              '已售完',
                              style: TextStyle(fontSize: 11.5, color: scheme.outline),
                            ),
                          ),
                        if (item.canGive)
                          OutlinedButton(
                            onPressed: _busy || item.mid.isEmpty ? null : () => _gift(item),
                            child: const Text('赠送'),
                          ),
                        if (item.canGive && !item.soldOut) const SizedBox(width: 8),
                        if (!item.soldOut)
                          FilledButton(
                            onPressed: _busy || item.mid.isEmpty ? null : () => _buy(item),
                            child: const Text('购买'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 我的道具
// ---------------------------------------------------------------------------

class _MagicBoxTab extends StatefulWidget {
  const _MagicBoxTab();

  @override
  State<_MagicBoxTab> createState() => _MagicBoxTabState();
}

class _MagicBoxTabState extends State<_MagicBoxTab> with AutomaticKeepAliveClientMixin {
  MagicBox _box = const MagicBox();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final box = await AppState.instance.repo.fetchMagicBox();
      if (!mounted) return;
      setState(() {
        _box = box;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(e, '加载失败，请稍后重试');
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _use(MyMagic item) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    var loading = true;
    showGlassDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog(text: '正在读取道具信息…'),
    );
    try {
      final form = await AppState.instance.repo.fetchMagicUseForm(item.id);
      if (loading) {
        loading = false;
        navigator.pop();
      }
      if (!mounted) return;
      final values = await showSiteFormDialog(
        context,
        title: '使用 ${item.name}',
        fields: form.fields,
        confirmText: '确认使用',
      );
      if (values == null || !mounted) return;
      setState(() => _busy = true);
      final message = await AppState.instance.repo.useMagic(
        magicId: item.id,
        form: form,
        values: values,
      );
      _toast(message);
      await _load();
    } catch (e) {
      if (loading) {
        loading = false;
        navigator.pop();
      }
      _toast(_errorText(e, '使用失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _give(MyMagic item) async {
    final request = await showGlassDialog<_MagicActionRequest>(
      context: context,
      builder: (_) => _MagicActionDialog(
        title: '赠送 ${item.name}',
        confirmText: '确认赠送',
        needUser: true,
        needMessage: true,
        maxNum: item.num,
      ),
    );
    if (request == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final message = await AppState.instance.repo.giveMagic(
        magicId: item.id,
        username: request.username,
        num: request.num,
        message: request.message,
      );
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_errorText(e, '赠送失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sell(MyMagic item) async {
    final request = await showGlassDialog<_MagicActionRequest>(
      context: context,
      builder: (_) => _MagicActionDialog(
        title: '出售 ${item.name}',
        confirmText: '确认出售',
        maxNum: item.num,
        description: '出售后按站点回收价折算积分。',
      ),
    );
    if (request == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final message = await AppState.instance.repo.sellMagic(magicId: item.id, num: request.num);
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_errorText(e, '出售失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _drop(MyMagic item) async {
    final request = await showGlassDialog<_MagicActionRequest>(
      context: context,
      builder: (_) => _MagicActionDialog(
        title: '丢弃 ${item.name}',
        confirmText: '确认丢弃',
        maxNum: item.num,
        description: '丢弃后无法找回。',
      ),
    );
    if (request == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final message = await AppState.instance.repo.dropMagic(magicId: item.id, num: request.num);
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_errorText(e, '丢弃失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    if (_loading) return SkeletonView(kind: SkeletonKind.row, topInset: glassTopInset(context));
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: glassPagePadding(context, top: 12, appBarBottom: kTextTabBarHeight),
        children: [
          _sectionTitle(scheme, '我的道具', '${_box.items.length} 种'),
          if (_box.capacity.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _box.capacity,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 10),
          if (_box.items.isEmpty)
            const EmptyView(text: '你还没有道具', icon: Icons.inventory_2_outlined)
          else
            for (final item in _box.items) ...[
              _card(
                scheme,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SmartImage(
                          url: item.image,
                          width: 44,
                          height: 44,
                          radius: BorderRadius.circular(10),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.weight.isEmpty
                                    ? '数量：${item.num}'
                                    : '数量：${item.num} · 重量：${item.weight}',
                                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, height: 1.45, color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (item.canUse)
                          FilledButton(
                            onPressed: _busy ? null : () => _use(item),
                            child: const Text('使用'),
                          ),
                        if (item.canGive)
                          OutlinedButton(
                            onPressed: _busy ? null : () => _give(item),
                            child: const Text('赠送'),
                          ),
                        if (item.canSell)
                          OutlinedButton(
                            onPressed: _busy ? null : () => _sell(item),
                            child: const Text('出售'),
                          ),
                        if (item.canDrop)
                          OutlinedButton(
                            onPressed: _busy ? null : () => _drop(item),
                            child: const Text('丢弃'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 记录
// ---------------------------------------------------------------------------

class _MagicLogTab extends StatefulWidget {
  const _MagicLogTab();

  @override
  State<_MagicLogTab> createState() => _MagicLogTabState();
}

class _MagicLogTabState extends State<_MagicLogTab> with AutomaticKeepAliveClientMixin {
  static const List<(String, String)> _types = [
    ('uselog', '使用'),
    ('buylog', '购买'),
    ('givelog', '赠送'),
    ('receivelog', '收到'),
  ];

  List<MagicLogEntry> _items = [];
  String _type = 'uselog';
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AppState.instance.repo.fetchMagicLogs(_type, page: 1);
      if (!mounted) return;
      setState(() {
        _items = items;
        _page = 1;
        _hasMore = items.length >= 20;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(e, '加载失败，请稍后重试');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final items = await AppState.instance.repo.fetchMagicLogs(_type, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _items = [..._items, ...items];
        _hasMore = items.length >= 20;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorText(e, '加载更多失败，请稍后重试'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(kPageGutter, glassTopInset(context, bottomHeight: kTextTabBarHeight) + 12, kPageGutter, 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: GlassSegmented<String>(
                    segments: [for (final entry in _types) (entry.$1, entry.$2)],
                    value: _type,
                    dense: true,
                    onChanged: (value) {
                      setState(() => _type = value);
                      _load();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          // 上面那行筛选器已经让过顶栏了，骨架不用再让一次。
          child: _loading
              ? const SkeletonView(kind: SkeletonKind.row)
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                        children: [
                          _sectionTitle(scheme, '道具记录', '${_items.length} 条'),
                          const SizedBox(height: 10),
                          if (_items.isEmpty)
                            const EmptyView(text: '暂无相关记录', icon: Icons.history_rounded)
                          else ...[
                            for (final item in _items) ...[
                              _card(
                                scheme,
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.title,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        if (item.time.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            item.time,
                                            style: TextStyle(fontSize: 10.5, color: scheme.outline),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (item.detail.isNotEmpty) ...[
                                      const SizedBox(height: 5),
                                      Text(
                                        item.detail,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          height: 1.4,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (_loadingMore)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            else if (_hasMore)
                              Center(
                                child: TextButton.icon(
                                  onPressed: _loadMore,
                                  icon: const Icon(Icons.expand_more_rounded, size: 18),
                                  label: const Text('加载更多'),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 对话框
// ---------------------------------------------------------------------------

class _MagicActionRequest {
  const _MagicActionRequest({required this.num, this.username = '', this.message = ''});

  final int num;
  final String username;
  final String message;
}

class _MagicActionDialog extends StatefulWidget {
  const _MagicActionDialog({
    required this.title,
    required this.confirmText,
    this.description = '',
    this.needUser = false,
    this.needMessage = false,
    this.maxNum = 99,
  });

  final String title;
  final String confirmText;
  final String description;
  final bool needUser;
  final bool needMessage;
  final int maxNum;

  @override
  State<_MagicActionDialog> createState() => _MagicActionDialogState();
}

class _MagicActionDialogState extends State<_MagicActionDialog> {
  late int _num = _clampNum(1);

  int _clampNum(int value) {
    final max = widget.maxNum < 1 ? 1 : widget.maxNum;
    if (value < 1) return 1;
    return value > max ? max : value;
  }
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _userController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.needUser && _userController.text.trim().isEmpty) {
      setState(() => _error = '请输入接收人的用户名');
      return;
    }
    Navigator.of(context).pop(_MagicActionRequest(
      num: _num,
      username: _userController.text.trim(),
      message: _messageController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.description.isNotEmpty) ...[
              Text(
                widget.description,
                style: TextStyle(fontSize: 12, height: 1.45, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                const Text('数量', style: TextStyle(fontSize: 13)),
                const Spacer(),
                IconButton(
                  onPressed: _num <= 1 ? null : () => setState(() => _num -= 1),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  visualDensity: VisualDensity.compact,
                ),
                SizedBox(
                  width: 34,
                  child: Text(
                    '$_num',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: _num >= widget.maxNum ? null : () => setState(() => _num += 1),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (widget.needUser) ...[
              const SizedBox(height: 10),
              GlassField(
                controller: _userController,
                label: '接收人用户名',
                leading: Icons.person_outline_rounded,
                textInputAction: TextInputAction.next,
              ),
            ],
            if (widget.needMessage) ...[
              const SizedBox(height: 10),
              GlassField(
                controller: _messageController,
                label: '留言（可选）',
                maxLines: 2,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(fontSize: 11.5, color: scheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmText)),
      ],
    );
  }
}

class _BusyDialog extends StatelessWidget {
  const _BusyDialog({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 14),
              Flexible(child: Text(text, style: const TextStyle(fontSize: 13))),
            ],
          ),
        ),
      ),
    );
  }
}

/// 使用道具时按站点要求填写的动态表单由 [showSiteFormDialog] 统一渲染。
