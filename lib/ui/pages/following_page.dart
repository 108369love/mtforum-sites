import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/glass_controls.dart';
import 'user_list_page.dart';
import '../widgets/glass_dialog.dart';

/// 当前账号关注的用户列表。
///
/// 列表本身交给 [UserListPage]；这里只保留三件事：改备注、星标、取消关注。
class FollowingPage extends StatelessWidget {
  const FollowingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return UserListPage(
      title: '我的关注',
      loginHint: '登录后查看我的关注',
      loginIcon: Icons.people_alt_outlined,
      emptyText: '还没有关注任何用户',
      emptyIcon: Icons.person_search_rounded,
      subtitle: userCountsSubtitle,
      loader: (page) async {
        final state = AppState.instance;
        var uid = state.profile?.uid ?? 0;
        if (uid <= 0) {
          await state.refreshProfile(silent: true);
          uid = AppState.instance.profile?.uid ?? 0;
        }
        if (uid <= 0) throw SiteException('无法识别当前账号，请刷新个人资料后重试');
        return state.repo.fetchFollowing(uid, page: page);
      },
      actions: (context, user, handle) => [
        IconButton(
          tooltip: '备注',
          visualDensity: VisualDensity.compact,
          onPressed: () => _editNote(context, user, handle),
          icon: Icon(Icons.edit_note_rounded, color: scheme.primary),
        ),
        IconButton(
          tooltip: user.isStarred ? '取消星标' : '星标',
          visualDensity: VisualDensity.compact,
          onPressed: () => _toggleStar(context, user, handle),
          icon: Icon(
            user.isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
            color: user.isStarred ? Colors.green : scheme.outline,
          ),
        ),
        IconButton(
          tooltip: '取消关注',
          visualDensity: VisualDensity.compact,
          onPressed: () => _cancelFollowing(context, user, handle),
          icon: const Icon(Icons.person_remove_alt_1_rounded, color: Colors.redAccent),
        ),
      ],
    );
  }

  Future<void> _cancelFollowing(BuildContext context, FriendItem user, UserListHandle handle) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('取消关注'),
        content: Text('确定不再关注「${user.username}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('保留关注')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('取消关注')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await AppState.instance.repo.cancelFollowing(user.uid);
      if (!context.mounted) return;
      handle.remove(user.uid);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已取消关注')));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is SiteException ? e.message : '取消关注失败')),
        );
      }
    }
  }

  Future<void> _editNote(BuildContext context, FriendItem user, UserListHandle handle) async {
    final controller = TextEditingController(text: user.note);
    final value = await showGlassDialog<String>(
      context: context,
      builder: (context) => GlassDialog(
        title: Text('备注：${user.username}'),
        content: GlassField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          label: '备注名称',
          hintText: '输入备注',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !context.mounted) return;
    try {
      final saved = await AppState.instance.repo.setFollowingNote(user.uid, value);
      if (!context.mounted) return;
      handle.replace(user.copyWith(note: saved));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('备注已保存')));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is SiteException ? e.message : '保存备注失败')),
        );
      }
    }
  }

  Future<void> _toggleStar(BuildContext context, FriendItem user, UserListHandle handle) async {
    try {
      await AppState.instance.repo.setFollowingStar(user.uid, starred: !user.isStarred);
      if (!context.mounted) return;
      handle.replace(user.copyWith(isStarred: !user.isStarred));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is SiteException ? e.message : '操作失败')),
        );
      }
    }
  }
}
