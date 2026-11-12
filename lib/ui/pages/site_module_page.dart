import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/smart_image.dart';
import '../widgets/state_views.dart';
import '../widgets/glass_app_bar.dart';
import 'mall_product_page.dart';
import 'thread_page.dart';
import 'user_page.dart';
import '../navigation/app_routes.dart';
import '../widgets/glass_dialog.dart';

/// 通用站点模块页：原生渲染道具、任务、积分、推广等页面里的条目。
class SiteModulePage extends StatefulWidget {
  const SiteModulePage({
    super.key,
    required this.title,
    required this.path,
    this.query = const {},
    this.icon = Icons.widgets_outlined,
    this.tip = '',
  });

  final String title;
  final String path;
  final Map<String, String> query;
  final IconData icon;
  final String tip;

  @override
  State<SiteModulePage> createState() => _SiteModulePageState();
}

class _SiteModulePageState extends State<SiteModulePage> {
  List<SiteRow> _rows = [];
  String _tip = '';
  bool _loading = true;
  String? _error;

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
      final (tip, rows) = await AppState.instance.repo.fetchModule(widget.path, widget.query);
      if (!mounted) return;
      setState(() {
        _tip = tip.isNotEmpty ? tip : widget.tip;
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is SiteException ? e.message : '加载失败，请稍后重试';
      });
    }
  }

  bool _isAction(String href) =>
      RegExp(r'[?&](action|ac|do|op)=(apply|buy|use|del|pay|exchange)').hasMatch(href);

  Future<void> _onTap(SiteRow row) async {
    final href = row.href;
    if (href.isEmpty) return;
    // 积分商城商品详情是插件页，不能当帖子打开。
    if (href.contains('keke_integralmall-view.html')) {
      final tid = RegExp(r'[?&]tid=(\d+)').firstMatch(href)?.group(1);
      if (tid != null) {
        await Navigator.of(context).push(
          appRoute(builder: (_) => MallProductPage(tid: int.parse(tid))),
        );
        return;
      }
    }
    final uid = RegExp(r'[?&]uid=(\d+)').firstMatch(href)?.group(1) ??
        RegExp(r'space-uid-(\d+)\.html').firstMatch(href)?.group(1);
    if (uid != null) {
      await Navigator.of(context).push(
        appRoute(builder: (_) => UserPage(uid: int.parse(uid), name: row.title)),
      );
      return;
    }
    final tid = RegExp(r'thread-(\d+)-\d+-\d+\.html').firstMatch(href)?.group(1) ??
        RegExp(r'[?&]tid=(\d+)').firstMatch(href)?.group(1);
    if (tid != null) {
      await Navigator.of(context).push(appRoute(builder: (_) => ThreadPage(tid: int.parse(tid))));
      return;
    }
    if (!_isAction(href)) {
      await launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
      return;
    }
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: Text(row.title),
        content: const Text('确认执行该操作？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('确认')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await AppState.instance.repo.performModuleAction(href);
      messenger.showSnackBar(SnackBar(content: Text(message)));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is SiteException ? e.message : '操作失败，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? SkeletonView(kind: SkeletonKind.card, topInset: glassTopInset(context))
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: glassPagePadding(context, top: 12),
                      children: [
                        if (_tip.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded, size: 18, color: scheme.onSecondaryContainer),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _tip,
                                    style: TextStyle(fontSize: 12.5, height: 1.5, color: scheme.onSecondaryContainer),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_rows.isEmpty)
                          EmptyView(text: '${widget.title}暂无内容', icon: widget.icon)
                        else
                          for (final row in _rows) ...[
                            _rowTile(scheme, row),
                            const SizedBox(height: 8),
                          ],
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _rowTile(ColorScheme scheme, SiteRow row) {
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onTap(row),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              if (row.image.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SmartImage(url: row.image, width: 38, height: 38, fit: BoxFit.cover),
                )
              else
                Icon(widget.icon, size: 26, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    if (row.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      _LiveCountdownSubtitle(
                        text: row.subtitle,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}


/// 积分商城列表的倒计时：以页面加载时站点返回的剩余时长建立本地截止时间，
/// 每秒按当前时间重新计算，避免简单递减造成后台恢复后计时漂移。
class _LiveCountdownSubtitle extends StatefulWidget {
  const _LiveCountdownSubtitle({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  State<_LiveCountdownSubtitle> createState() => _LiveCountdownSubtitleState();
}

class _LiveCountdownSubtitleState extends State<_LiveCountdownSubtitle> {
  static final RegExp _countdownPattern = RegExp(
    r'剩余\s*(\d+)\s*天\s*(\d+)\s*小时\s*(\d+)\s*分\s*(\d+)\s*秒',
  );

  Timer? _timer;
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void didUpdateWidget(covariant _LiveCountdownSubtitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _timer?.cancel();
      _deadline = null;
      _startCountdown();
    }
  }

  void _startCountdown() {
    final match = _countdownPattern.firstMatch(widget.text);
    if (match == null) return;
    final days = int.tryParse(match.group(1)!) ?? 0;
    final hours = int.tryParse(match.group(2)!) ?? 0;
    final minutes = int.tryParse(match.group(3)!) ?? 0;
    final seconds = int.tryParse(match.group(4)!) ?? 0;
    _deadline = DateTime.now().add(
      Duration(days: days, hours: hours, minutes: minutes, seconds: seconds),
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  String _displayText() {
    final deadline = _deadline;
    if (deadline == null) return widget.text;
    final left = deadline.difference(DateTime.now());
    if (left <= Duration.zero) {
      return widget.text.replaceFirst(_countdownPattern, '活动已结束');
    }
    final days = left.inDays;
    final hours = left.inHours % 24;
    final minutes = left.inMinutes % 60;
    final seconds = left.inSeconds % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    final value = '剩余 $days天${two(hours)}小时${two(minutes)}分${two(seconds)}秒';
    return widget.text.replaceFirst(_countdownPattern, value);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayText(),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11.5, height: 1.4, color: widget.color),
    );
  }
}
