import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../navigation/app_routes.dart';
import 'pm_chat_page.dart';
import 'user_list_page.dart';

/// 我的好友：好友列表，可进入主页或直接私聊。
///
/// 加载、空态、登录态、行布局都在 [UserListPage] 里，这里只剩下差异部分。
class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return UserListPage(
      title: '我的好友',
      // 好友一次给全，不需要滚动加载。
      paged: false,
      loginHint: '登录后查看我的好友',
      loginIcon: Icons.group_outlined,
      emptyText: '你还没有好友',
      emptyIcon: Icons.group_outlined,
      loader: (_) => AppState.instance.repo.fetchFriends(),
      subtitle: (user) => user.note.isEmpty ? 'UID ${user.uid}' : user.note,
      actions: (context, user, _) => [
        IconButton(
          tooltip: '发私信',
          onPressed: () => Navigator.of(context).push(
            appRoute(builder: (_) => PmChatPage(uid: user.uid, name: user.username)),
          ),
          icon: Icon(Icons.mail_outline_rounded, size: 20, color: scheme.primary),
        ),
      ],
    );
  }
}
