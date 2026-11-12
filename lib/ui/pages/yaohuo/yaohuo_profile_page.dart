import 'package:flutter/material.dart';
import 'package:in_app_webview_flutter/flutter_inappwebview.dart';

import '../../../core/yaohuo_session.dart';
import '../../../data/yaohuo_repository.dart';
import '../../navigation/app_routes.dart';
import '../about_page.dart';
import '../internal_browser_page.dart';
import '../site_picker_page.dart';
import '../userscripts_page.dart';
import 'yaohuo_auto_list_page.dart';
import 'yaohuo_compose_page.dart';
import 'yaohuo_login_page.dart';

/// 妖火的「我的」：账号状态 + 几个入口。
class YaohuoProfilePage extends StatefulWidget {
  const YaohuoProfilePage({super.key});

  @override
  State<YaohuoProfilePage> createState() => _YaohuoProfilePageState();
}

class _YaohuoProfilePageState extends State<YaohuoProfilePage> {
  bool _checking = true;
  bool _loggedIn = false;
  List<({String label, String url})> _nav = <({String label, String url})>[];

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    await YaohuoSession.instance.refresh();
    final loggedIn = YaohuoSession.instance.hasSession;
    var nav = <({String label, String url})>[];
    if (loggedIn) {
      try {
        nav = await YaohuoRepository.instance.fetchMyNav();
      } catch (_) {
        nav = <({String label, String url})>[];
      }
    }
    if (!mounted) return;
    setState(() {
      _loggedIn = loggedIn;
      _nav = nav;
      _checking = false;
    });
  }

  Future<void> _login() async {
    final ok = await Navigator.of(context).push<bool>(appRoute(builder: (_) => const YaohuoLoginPage()));
    if (ok == true) await _check();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出妖火登录'),
        content: const Text('会清掉内置浏览器里妖火域的 Cookie，下次要重新登录（含人机验证）。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await CookieManager.instance().deleteCookies(url: WebUri(YaohuoSession.base));
    } catch (_) {
      // 清不掉也把本地这份会话丢掉。
    }
    await YaohuoSession.instance.clear();
    await _check();
  }

  void _open(Widget page) {
    Navigator.of(context).push(appRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(tooltip: '刷新登录状态', onPressed: _check, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [scheme.primary.withValues(alpha: 0.90), scheme.primary.withValues(alpha: 0.60)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 26),
                    const SizedBox(width: 8),
                    const Text('妖火网', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_checking)
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _loggedIn ? '已登录' : '未登录',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _loggedIn
                      ? '原生解析已就绪：列表、帖子、回复都走本地请求。'
                      : '登录页带人机验证，需要在内置浏览器里完成一次登录。',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: scheme.primary,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _checking ? null : (_loggedIn ? _check : _login),
                      child: Text(_loggedIn ? '刷新状态' : '登录妖火'),
                    ),
                    if (_loggedIn) ...[
                      const SizedBox(width: 10),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        onPressed: _logout,
                        child: const Text('退出登录'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_loggedIn && _nav.isNotEmpty) ...[
            _group(scheme, [
              for (final entry in _nav)
                ListTile(
                  leading: Icon(_navIcon(entry.label), size: 21, color: scheme.onSurfaceVariant),
                  title: Text(entry.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(entry.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                  trailing: Icon(Icons.chevron_right_rounded, size: 20, color: scheme.outline),
                  onTap: () => _open(InternalBrowserPage(url: entry.url, title: entry.label)),
                ),
            ]),
            const SizedBox(height: 14),
          ],
          _group(scheme, [
            ListTile(
              leading: Icon(Icons.star_outline_rounded, size: 21, color: scheme.onSurfaceVariant),
              title: const Text('我的收藏', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              trailing: Icon(Icons.chevron_right_rounded, size: 20, color: scheme.outline),
              onTap: () => _open(const YaohuoAutoListPage(
                url: 'https://yaohuo.me/bbs/favlist.aspx?siteid=1000&classid=0',
                title: '我的收藏',
              )),
            ),
            ListTile(
              leading: Icon(Icons.people_outline_rounded, size: 21, color: scheme.onSurfaceVariant),
              title: const Text('好友', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              trailing: Icon(Icons.chevron_right_rounded, size: 20, color: scheme.outline),
              onTap: () => _open(const YaohuoAutoListPage(
                url: 'https://yaohuo.me/bbs/FriendList.aspx?siteid=1000&classid=0&friendtype=0',
                title: '好友',
              )),
            ),
            ListTile(
              leading: Icon(Icons.add_box_outlined, size: 21, color: scheme.onSurfaceVariant),
              title: const Text('发帖', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              trailing: Icon(Icons.chevron_right_rounded, size: 20, color: scheme.outline),
              onTap: () => _open(const YaohuoComposePage()),
            ),
          ]),
          const SizedBox(height: 14),
          _group(scheme, [
            ListTile(
              leading: Icon(Icons.open_in_browser_rounded, size: 21, color: scheme.onSurfaceVariant),
              title: const Text('用浏览器打开妖火', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              trailing: Icon(Icons.chevron_right_rounded, size: 20, color: scheme.outline),
              onTap: () => _open(const InternalBrowserPage(url: 'https://yaohuo.me/', title: '妖火网')),
            ),
            ListTile(
              leading: Icon(Icons.swap_horiz_rounded, size: 21, color: scheme.onSurfaceVariant),
              title: const Text('切换站点', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              trailing: Icon(Icons.chevron_right_rounded, size: 20, color: scheme.outline),
              onTap: () => _open(const SitePickerPage()),
            ),
          ]),
          const SizedBox(height: 14),
          _group(scheme, [
            ListTile(
              leading: Icon(Icons.extension_outlined, size: 21, color: scheme.onSurfaceVariant),
              title: const Text('用户脚本', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              trailing: Icon(Icons.chevron_right_rounded, size: 20, color: scheme.outline),
              onTap: () => _open(const UserScriptsPage()),
            ),
            ListTile(
              leading: Icon(Icons.info_outline_rounded, size: 21, color: scheme.onSurfaceVariant),
              title: const Text('关于本应用', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              trailing: Icon(Icons.chevron_right_rounded, size: 20, color: scheme.outline),
              onTap: () => _open(const AboutPage()),
            ),
          ]),
          const SizedBox(height: 22),
          Text(
            '妖火网 · ${_loggedIn ? '已登录' : '未登录'}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
        ],
      ),
    );
  }

  IconData _navIcon(String label) {
    if (label == '我的地盘') return Icons.space_dashboard_outlined;
    if (label == '空间') return Icons.person_outline_rounded;
    if (label == '帖子') return Icons.article_outlined;
    if (label == '信箱') return Icons.mail_outline_rounded;
    return Icons.link_rounded;
  }

  Widget _group(ColorScheme scheme, List<Widget> children) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.45)),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
