import 'package:flutter/material.dart';

import '../../../data/yaohuo_repository.dart';
import 'yaohuo_thread_list.dart';

/// 全站热门：站点按时间窗（一天内/三天内/一周内/一月内）给排行榜。
class YaohuoHotPage extends StatefulWidget {
  const YaohuoHotPage({super.key});

  @override
  State<YaohuoHotPage> createState() => _YaohuoHotPageState();
}

class _YaohuoHotPageState extends State<YaohuoHotPage> {
  static const List<({String label, int days})> _ranges = <({String label, int days})>[
    (label: '一天内', days: 1),
    (label: '三天内', days: 3),
    (label: '一周内', days: 7),
    (label: '一月内', days: 30),
  ];

  int _days = 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('热门')),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: _ranges.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final range = _ranges[index];
                final selected = range.days == _days;
                return ChoiceChip(
                  label: Text(range.label, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: scheme.primary.withValues(alpha: 0.16),
                  labelStyle: TextStyle(
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  onSelected: (_) => setState(() => _days = range.days),
                );
              },
            ),
          ),
          Expanded(
            child: YaohuoThreadListView(
              key: ValueKey<String>('yaohuo-hot-$_days'),
              loader: (page) => YaohuoRepository.instance.fetchHotThreads(days: _days, page: page),
              emptyText: '这个时间窗里没有热门帖',
            ),
          ),
        ],
      ),
    );
  }
}
