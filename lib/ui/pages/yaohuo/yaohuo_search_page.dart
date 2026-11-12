import 'package:flutter/material.dart';

import '../../../data/yaohuo_repository.dart';
import 'yaohuo_thread_list.dart';

/// 妖火搜索：站内按标题搜。
class YaohuoSearchPage extends StatefulWidget {
  const YaohuoSearchPage({super.key});

  @override
  State<YaohuoSearchPage> createState() => _YaohuoSearchPageState();
}

class _YaohuoSearchPageState extends State<YaohuoSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final text = value.trim();
    _focus.unfocus();
    if (text.isEmpty) return;
    setState(() => _query = text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              decoration: InputDecoration(
                hintText: '搜妖火的帖子标题',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  onPressed: () => _submit(_controller.text),
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _query.isEmpty
                ? Center(
                    child: Text(
                      '输入关键词，回车开始搜索',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  )
                : YaohuoThreadListView(
                    key: ValueKey<String>('yaohuo-search-$_query'),
                    loader: (page) => YaohuoRepository.instance.fetchThreads(
                      action: YaohuoRepository.actionSearch,
                      page: page,
                      key: _query,
                    ),
                    emptyText: '没有搜到相关帖子',
                  ),
          ),
        ],
      ),
    );
  }
}
