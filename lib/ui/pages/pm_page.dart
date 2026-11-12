import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/forum_repository.dart';
import '../widgets/user_avatar.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_controls.dart';

/// 站内私信：给指定用户发送一条私信。
class PmPage extends StatefulWidget {
  const PmPage({super.key, required this.uid, required this.name});

  final int uid;
  final String name;

  @override
  State<PmPage> createState() => _PmPageState();
}

class _PmPageState extends State<PmPage> {
  final ForumRepository _repo = ForumRepository.instance;
  final TextEditingController _controller = TextEditingController();

  String _formhash = '';
  String _avatar = '';
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final info = await _repo.fetchUserProfile(widget.uid);
      if (!mounted) return;
      setState(() {
        _formhash = info.$2;
        _avatar = info.$1.avatar;
        _loading = false;
        _error = _formhash.isEmpty ? '未能获取发送凭证，请稍后重试' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  String _message(Object error) => error is SiteException ? error.message : '$error';

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final message = await _repo.sendPm(
        uid: widget.uid,
        formhash: _formhash,
        message: text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('发送私信')),
      body: ListView(
        padding: glassPagePadding(context, top: 16),
        children: [
          Row(
            children: [
              UserAvatar(url: _avatar, size: 40, name: widget.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('收件人：${widget.name}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    Text('UID ${widget.uid}', style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.outline)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else ...[
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12.5)),
              ),
            GlassField(
              controller: _controller,
              minLines: 6,
              maxLines: 12,
              maxLength: 500,
              hintText: '输入私信内容…',
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _sending || _formhash.isEmpty ? null : _send,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(_sending ? '发送中…' : '发送'),
            ),
          ],
        ],
      ),
    );
  }
}
