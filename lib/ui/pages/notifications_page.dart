import 'package:flutter/material.dart';

import 'followers_page.dart';
import 'native_notice_category_page.dart';
import 'pm_list_page.dart';
import '../navigation/app_routes.dart';
import '../widgets/glass_app_bar.dart';

/// 消息通知：私信、粉丝与各类提醒。全部为原生页面。
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  Future<void> _openCategory(String title, String view) async {
    await Navigator.of(context).push(appRoute(
      builder: (_) => NativeNoticeCategoryPage(title: title, view: view),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const categories = <({String title, String subtitle, IconData icon, Color color, String view})>[
      (title: '我的消息', subtitle: '私信与会话', icon: Icons.chat_bubble_rounded, color: Color(0xFF55B8E8), view: ''),
      (title: '我的粉丝', subtitle: '关注我的坛友', icon: Icons.groups_rounded, color: Color(0xFFE97D8A), view: ''),
      (title: '我的帖子', subtitle: '帖子被回复、评论提醒', icon: Icons.forum_rounded, color: Color(0xFF9BC20D), view: 'mypost'),
      (title: '坛友互动', subtitle: '关注、点赞与 @ 提醒', icon: Icons.send_rounded, color: Color(0xFFF5B400), view: 'interactive'),
      (title: '系统提醒', subtitle: '系统通知与管理提醒', icon: Icons.notifications_active_rounded, color: Color(0xFFE97D8A), view: 'system'),
      (title: '应用提醒', subtitle: '应用相关通知', icon: Icons.sensors_rounded, color: Color(0xFF8BB5E4), view: 'app'),
    ];
    final topInset = glassTopInset(context);
    return Scaffold(
      // 列表从玻璃顶栏背后滚过。
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('消息提醒')),
      body: ListView.separated(
        padding: EdgeInsets.only(top: topInset),
        itemCount: categories.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.45)),
        itemBuilder: (context, index) {
          final item = categories[index];
          return ListTile(
            minVerticalPadding: 16,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
              child: Icon(item.icon, color: Colors.white, size: 25),
            ),
            title: Text(item.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            subtitle: Text(item.subtitle, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.outline),
            onTap: () {
              if (item.title == '我的消息') {
                Navigator.of(context).push(appRoute(builder: (_) => const PmListPage()));
              } else if (item.title == '我的粉丝') {
                Navigator.of(context).push(appRoute(builder: (_) => const FollowersPage()));
              } else {
                _openCategory(item.title, item.view);
              }
            },
          );
        },
      ),
    );
  }

}
