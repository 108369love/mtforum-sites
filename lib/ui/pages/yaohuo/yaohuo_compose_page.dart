import 'package:flutter/material.dart';

import '../../../data/yaohuo_repository.dart';
import '../../navigation/app_routes.dart';

/// 妖火发帖页：板块 + 标题 + 内容（+ 可选悬赏）。
///
/// 站点发帖表单的隐藏字段（__CSRFToken/action/classid/siteid）每次都会变，所以
/// 不在本地拼死，而是先抓 `book_view_add.aspx` 的原表单、填好再提交。
class YaohuoComposePage extends StatefulWidget {
  const YaohuoComposePage({super.key, this.initialClassId = 177});

  final int initialClassId;

  @override
  State<YaohuoComposePage> createState() => _YaohuoComposePageState();
}

class _YaohuoComposePageState extends State<YaohuoComposePage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();
  final TextEditingController _money = TextEditingController();
  late int _classId = widget.initialClassId;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _money.dispose();
    super.dispose();
  }

  String get _boardName {
    for (final board in YaohuoRepository.boards) {
      if (board.id == _classId) return board.name;
    }
    return '板块 $_classId';
  }

  Future<void> _pickBoard() async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text('选择板块', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final board in YaohuoRepository.boards)
              ListTile(
                title: Text(board.name),
                trailing: board.id == _classId ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(sheetContext, board.id),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) setState(() => _classId = chosen);
  }

  Future<void> _publish() async {
    if (_sending) return;
    final title = _title.text.trim();
    final content = _content.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('标题不能为空')));
      return;
    }
    if (content.length < 15) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('正文至少 15 个字（站点限制）')));
      return;
    }
    setState(() => _sending = true);
    final message = await YaohuoRepository.instance.publish(
      classId: _classId,
      title: title,
      content: content,
      sendmoney: _money.text.trim(),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    if (message.contains('成功')) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('发表新主题'),
        actions: [
          TextButton(
            onPressed: _sending ? null : _publish,
            child: _sending ? const Text('发布中…') : const Text('发布'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: _pickBoard,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: '板块',
                border: OutlineInputBorder(),
                isDense: true,
                suffixIcon: Icon(Icons.expand_more_rounded, size: 20),
              ),
              child: Text(_boardName),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            maxLength: 60,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '标题',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _content,
            minLines: 8,
            maxLines: 16,
            maxLength: 5000,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              labelText: '内容',
              hintText: '帖子发到对应版块，以免被删除。',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _money,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '悬赏妖晶（可选）',
              hintText: '不填就是普通帖',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _sending ? null : _publish,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(_sending ? '发布中…' : '发表新帖'),
          ),
          const SizedBox(height: 18),
          Text(
            '提示：正文至少 15 字；发布成功后回列表刷新就能看到。'
            '派币帖 / 投票帖 / 资源帖这些特殊类型暂时只能在浏览器里发。',
            style: TextStyle(fontSize: 11, height: 1.6, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
