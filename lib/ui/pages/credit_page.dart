import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_controls.dart';
import '../widgets/state_views.dart';

/// 积分：余额摘要与交易记录（原生渲染）。
class CreditPage extends StatefulWidget {
  const CreditPage({super.key});

  @override
  State<CreditPage> createState() => _CreditPageState();
}

class _CreditPageState extends State<CreditPage> {
  static const int _pageSize = 20;

  CreditSummary _summary = const CreditSummary();
  final List<CreditLog> _logs = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 1;

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
      final summary = await AppState.instance.repo.fetchCredits();
      final logs = await AppState.instance.repo.fetchCreditLogs(page: 1);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _logs
          ..clear()
          ..addAll(logs);
        _page = 1;
        _hasMore = logs.length >= _pageSize;
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final logs = await AppState.instance.repo.fetchCreditLogs(page: _page + 1);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _logs.addAll(logs);
        _hasMore = logs.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is SiteException ? e.message : '加载更多失败，请稍后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('积分'),
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
            ? SkeletonView(kind: SkeletonKind.row, topInset: glassTopInset(context))
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: glassPagePadding(context, top: 12),
                      children: [
                        _balanceCard(scheme),
                        const SizedBox(height: 20),
                        _sectionTitle(scheme, '交易记录', '最近 ${_logs.length} 条'),
                        const SizedBox(height: 10),
                        if (_logs.isEmpty)
                          const EmptyView(text: '暂无积分交易记录', icon: Icons.receipt_long_outlined)
                        else ...[
                          for (final log in _logs) ...[
                            _logTile(scheme, log),
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
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Center(
                                child: Text(
                                  '没有更多记录了',
                                  style: TextStyle(fontSize: 11.5, color: scheme.outline),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _balanceCard(ColorScheme scheme) {
    final items = _summary.items;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.toll_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              const Text('积分余额', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_summary.total.isNotEmpty)
                Text(
                  '总积分 ${_summary.total}',
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text('站点暂未返回积分明细', style: TextStyle(fontSize: 12, color: scheme.outline))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in items)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.name,
                          style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.value,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: item.highlight ? scheme.primary : scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          if (_summary.formula.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _summary.formula,
              style: TextStyle(fontSize: 10.5, height: 1.4, color: scheme.outline),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(ColorScheme scheme, String title, String trailing) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Text(trailing, style: TextStyle(fontSize: 11, color: scheme.outline)),
      ],
    );
  }

  Widget _logTile(ColorScheme scheme, CreditLog log) {
    final change = log.change.trim();
    final color = change.startsWith('-')
        ? scheme.error
        : change.startsWith('+')
            ? scheme.primary
            : scheme.onSurfaceVariant;
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log.operation, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                if (log.detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    log.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, height: 1.4, color: scheme.onSurfaceVariant),
                  ),
                ],
                if (log.time.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(log.time, style: TextStyle(fontSize: 10.5, color: scheme.outline)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            change,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}
