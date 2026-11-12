import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../state/app_state.dart';
import 'user_list_page.dart';

/// 我的粉丝：站点 `home.php?mod=follow&do=follower` 的原生列表。
///
/// 每行显示头像、昵称与「关注 / 粉丝」数量，点击进入对方主页；
/// 不再把「6 关注」这种计数链接当成昵称渲染。
class FollowersPage extends StatelessWidget {
  const FollowersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return UserListPage(
      title: '我的粉丝',
      loginHint: '登录后查看我的粉丝',
      loginIcon: Icons.people_outline_rounded,
      emptyText: '还没有粉丝',
      emptyIcon: Icons.people_outline_rounded,
      subtitle: userCountsSubtitle,
      loader: (page) async {
        final state = AppState.instance;
        var uid = state.profile?.uid ?? 0;
        if (uid <= 0) {
          await state.refreshProfile(silent: true);
          uid = AppState.instance.profile?.uid ?? 0;
        }
        if (uid <= 0) throw SiteException('无法识别当前账号，请刷新个人资料后重试');
        return state.repo.fetchFollowers(uid, page: page);
      },
    );
  }
}
