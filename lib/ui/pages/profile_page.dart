import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_compose_button.dart';
import '../widgets/thread_glass.dart';
import '../widgets/sign_in_badge.dart';
import '../widgets/thread_feed.dart';
import '../widgets/user_avatar.dart';
import 'about_page.dart';
import 'black_house_page.dart';
import 'browse_history_page.dart';
import 'credit_page.dart';
import 'friends_page.dart';
import 'followers_page.dart';
import 'following_page.dart';
import 'login_page.dart';
import 'notifications_page.dart';
import 'privacy_settings_page.dart';
import 'profile_settings_page.dart';
import 'rename_request_page.dart';
import 'user_group_page.dart';
import 'pm_list_page.dart';
import 'rankings_page.dart';
import 'site_features_page.dart';
import 'site_picker_page.dart';
import 'tags_page.dart';
import 'download_manager_page.dart';
import 'mcp_page.dart';
import 'offline_cache_page.dart';
import 'user_page.dart';
import '../navigation/app_routes.dart';
import '../widgets/cookie_dialog.dart';
import '../widgets/glass_dialog.dart';
import '../widgets/read_palette_sheet.dart';

/// 个人中心：账号信息、我的主题 / 回复 / 收藏、外观与退出。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (AppState.instance.isLoggedIn && AppState.instance.profile == null) {
      AppState.instance.refreshProfile();
    }
  }

  Future<void> _refresh() async {
    if (!AppState.instance.isLoggedIn) return;
    await AppState.instance.refreshProfile(silent: false);
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      noSwipeRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('登录成功')));
    }
  }

  Future<void> _copyCookie() async {
    final copied = await showCookieDialog(context);
    if (!mounted || !copied) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Cookie 已复制到剪贴板')));
  }

  Future<void> _logout() async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('退出登录'),
        content: const Text('退出后将无法发帖、回复与收藏，确定要退出吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出')),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppState.instance.logout();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已退出登录')));
  }

  Future<void> _pickTheme() async {
    final current = AppState.instance.themeMode;
    final options = <(ThemeMode, String, IconData)>[
      (ThemeMode.system, '跟随系统', Icons.brightness_auto_rounded),
      (ThemeMode.light, '浅色模式', Icons.light_mode_rounded),
      (ThemeMode.dark, '深色模式', Icons.dark_mode_rounded),
    ];
    final mode = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text('主题外观', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final option in options)
              ListTile(
                leading: Icon(option.$3),
                title: Text(option.$2),
                trailing: current == option.$1 ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(context, option.$1),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (mode != null) await AppState.instance.setThemeMode(mode);
  }

  /// 「液态玻璃」总入口。
  ///
  /// 底栏和发帖按钮用的是同一套材质，只是长在两块地方。原来分成两个入口，
  /// 想把两处调成一致得来回开关两个面板，这里合成一个：
  /// 上半节调底栏（带启用开关），下半节调发帖按钮，参数仍然各存各的。
  Future<void> _pickLiquidGlass() async {
    final appState = AppState.instance;
    var navEnabled = appState.floatingGlassNav;
    var navOpacity = appState.floatingGlassNavOpacity;
    var navBlur = appState.floatingGlassNavBlur;
    var composeOpacity = appState.composeGlassOpacity;
    var composeBlur = appState.composeGlassBlur;
    var threadOpacity = appState.threadGlassOpacity;
    var threadBlur = appState.threadGlassBlur;
    final scheme = Theme.of(context).colorScheme;

    final result = await showModalBottomSheet<({
      bool navEnabled,
      double navOpacity,
      double navBlur,
      double composeOpacity,
      double composeBlur,
      double threadOpacity,
      double threadBlur,
    })>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 22 + MediaQuery.viewInsetsOf(context).bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text('液态玻璃', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '底栏、发帖按钮、页面顶栏与输入条各自一套玻璃材质，透明度和模糊度分开调，保存后立即生效。',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: 18),

                  _glassSectionHeader(
                    context,
                    Icons.blur_on_rounded,
                    '底部导航栏',
                    '保持现有底栏形状，只换背景材质',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用液态玻璃悬浮底栏'),
                    subtitle: const Text('关闭后恢复普通底部导航栏'),
                    value: navEnabled,
                    onChanged: (value) => setSheetState(() => navEnabled = value),
                  ),
                  _glassSlider(
                    label: '玻璃透明度',
                    value: navOpacity,
                    min: 0.05,
                    max: 0.65,
                    divisions: 12,
                    onChanged: (value) => setSheetState(() => navOpacity = value),
                  ),
                  _glassSlider(
                    label: '背景模糊度',
                    value: navBlur,
                    min: 0,
                    max: 40,
                    divisions: 16,
                    percent: false,
                    onChanged: (value) => setSheetState(() => navBlur = value),
                  ),

                  const SizedBox(height: 18),
                  Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
                  const SizedBox(height: 18),

                  _glassSectionHeader(
                    context,
                    Icons.auto_awesome_rounded,
                    '发帖按钮',
                    '右下角悬浮按钮的玻璃材质，可边调边看预览',
                  ),
                  const SizedBox(height: 12),
                  // 实时预览：玻璃按钮压在色块上，能直观看出模糊强度。
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      height: 104,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.primaryContainer,
                            scheme.tertiaryContainer,
                            scheme.secondaryContainer,
                          ],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            left: 18,
                            top: 18,
                            child: Container(
                              width: 96,
                              height: 11,
                              decoration: BoxDecoration(
                                color: scheme.onPrimaryContainer.withValues(alpha: 0.28),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 18,
                            top: 38,
                            child: Container(
                              width: 148,
                              height: 11,
                              decoration: BoxDecoration(
                                color: scheme.onPrimaryContainer.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 18,
                            bottom: 18,
                            child: GlassComposeButton(
                              opacity: composeOpacity,
                              blur: composeBlur,
                              onPressed: () {},
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _glassSlider(
                    label: '玻璃透明度',
                    value: composeOpacity,
                    min: 0.05,
                    max: 0.75,
                    divisions: 14,
                    onChanged: (value) => setSheetState(() => composeOpacity = value),
                  ),
                  _glassSlider(
                    label: '背景模糊度',
                    value: composeBlur,
                    min: 0,
                    max: 40,
                    divisions: 16,
                    percent: false,
                    onChanged: (value) => setSheetState(() => composeBlur = value),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setSheetState(() {
                        composeOpacity = 0.28;
                        composeBlur = 26;
                      }),
                      child: const Text('发帖按钮恢复默认'),
                    ),
                  ),

                  const SizedBox(height: 18),
                  Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
                  const SizedBox(height: 18),

                  _glassSectionHeader(
                    context,
                    Icons.layers_rounded,
                    '顶栏与输入条',
                    '帖子页、私信、发帖、版块等页面的顶栏和悬浮输入区共用一套材质',
                  ),
                  const SizedBox(height: 12),
                  // 预览：上下两条玻璃压在同一块色块上，顶栏和回复框的观感一起看。
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      height: 132,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [scheme.primaryContainer, scheme.tertiaryContainer],
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 44, 14, 50),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _previewBar(scheme, 168, 0.30),
                                  const SizedBox(height: 10),
                                  _previewBar(scheme, 238, 0.20),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: GlassBackdrop(
                              opacity: threadOpacity,
                              blur: threadBlur,
                              showBorder: false,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                child: Row(
                                  children: [
                                    Icon(Icons.arrow_back_rounded, size: 17, color: scheme.onSurface),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '帖子标题',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    Icon(Icons.ios_share_rounded, size: 16, color: scheme.onSurfaceVariant),
                                    const SizedBox(width: 10),
                                    Icon(Icons.more_vert_rounded, size: 16, color: scheme.onSurfaceVariant),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: GlassBackdrop(
                              opacity: threadOpacity,
                              blur: threadBlur,
                              showBorder: false,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    Icon(Icons.sentiment_satisfied_alt_rounded, size: 17, color: scheme.onSurfaceVariant),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Container(
                                        height: 28,
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        decoration: BoxDecoration(
                                          color: scheme.surface.withValues(alpha: 0.55),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Text(
                                          '写下你的回复…',
                                          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(Icons.image_outlined, size: 17, color: scheme.onSurfaceVariant),
                                    const SizedBox(width: 8),
                                    Icon(Icons.send_rounded, size: 17, color: scheme.primary),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _glassSlider(
                    label: '玻璃透明度',
                    value: threadOpacity,
                    min: 0.05,
                    max: 0.85,
                    divisions: 16,
                    onChanged: (value) => setSheetState(() => threadOpacity = value),
                  ),
                  _glassSlider(
                    label: '背景模糊度',
                    value: threadBlur,
                    min: 0,
                    max: 40,
                    divisions: 16,
                    percent: false,
                    onChanged: (value) => setSheetState(() => threadBlur = value),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setSheetState(() {
                        threadOpacity = 0.55;
                        threadBlur = 22;
                      }),
                      child: const Text('恢复默认'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        sheetContext,
                        (
                          navEnabled: navEnabled,
                          navOpacity: navOpacity,
                          navBlur: navBlur,
                          composeOpacity: composeOpacity,
                          composeBlur: composeBlur,
                          threadOpacity: threadOpacity,
                          threadBlur: threadBlur,
                        ),
                      ),
                      child: const Text('保存设置'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == null) return;
    await appState.setFloatingGlassNav(result.navEnabled);
    await appState.setFloatingGlassNavAppearance(
      opacity: result.navOpacity,
      blur: result.navBlur,
    );
    await appState.setComposeGlassAppearance(
      opacity: result.composeOpacity,
      blur: result.composeBlur,
    );
    await appState.setThreadGlassAppearance(
      opacity: result.threadOpacity,
      blur: result.threadBlur,
    );
  }

  /// 帖子页预览里的一条「假文字」，用色块代替真实文本。
  Widget _previewBar(ColorScheme scheme, double width, double alpha) => Container(
        width: width,
        height: 10,
        decoration: BoxDecoration(
          color: scheme.onPrimaryContainer.withValues(alpha: alpha),
          borderRadius: BorderRadius.circular(6),
        ),
      );

  /// 玻璃面板里的小节标题，图标 + 名称 + 一句解释，比纯文字分组好认。
  Widget _glassSectionHeader(BuildContext context, IconData icon, String title, String desc) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(desc, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  /// 一条「名称 + 数值 + 滑杆」，两个玻璃部位各用两条。
  Widget _glassSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    bool percent = true,
  }) {
    // 透明度按百分比显示，模糊度直接给数值，两者量纲不一样。
    final text = percent ? '${(value * 100).round()}%' : value.round().toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(text, style: const TextStyle(fontSize: 12.5)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: text,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Future<void> _pickThemeColor() async {
    const colors = <(String, Color)>[
      ('薄荷绿', Color(0xFF12B76A)),
      ('海洋蓝', Color(0xFF2878D0)),
      ('天空蓝', Color(0xFF039BE5)),
      ('薰衣草紫', Color(0xFF8B5CF6)),
      ('玫瑰粉', Color(0xFFE84A8A)),
      ('珊瑚红', Color(0xFFE45454)),
      ('琥珀橙', Color(0xFFEF8B2C)),
      ('日落金', Color(0xFFC49A18)),
      ('青碧色', Color(0xFF009688)),
      ('石墨灰', Color(0xFF607080)),
    ];
    final current = AppState.instance.themeSeedColor;
    final selected = await showModalBottomSheet<Color>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择主题色', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('更改后会立即应用，并自动保存', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 14,
                children: [
                  for (final option in colors)
                    SizedBox(
                      width: 88,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(context, option.$2),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: option.$2,
                                  shape: BoxShape.circle,
                                  border: current.toARGB32() == option.$2.toARGB32()
                                      ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                                      : null,
                                ),
                                child: current.toARGB32() == option.$2.toARGB32()
                                    ? const Icon(Icons.check_rounded, color: Colors.white)
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              Text(option.$1, style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) await AppState.instance.setThemeSeedColor(selected);
  }

  void _openPersonal(String title, String path, Map<String, String> query, String emptyText,
      {bool replies = false}) {
    Navigator.of(context).push(appRoute(
      builder: (_) => _PersonalThreadsPage(
        title: title,
        path: path,
        query: query,
        emptyText: emptyText,
        replies: replies,
      ),
    ));
  }

  void _openPage(Widget page) {
    Navigator.of(context).push(appRoute(builder: (_) => page));
  }

  void _openMyLevel() {
    _openPage(const UserGroupPage());
  }

  void _openMySpace() {
    final profile = AppState.instance.profile;
    if (profile == null || profile.uid <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('资料加载中，请稍后重试')));
      _refresh();
      return;
    }
    _openPage(UserPage(uid: profile.uid, name: profile.username));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final profile = state.profile;
        final topInset = glassTopInset(context);
        return Scaffold(
          // 资料卡和菜单从玻璃顶栏背后滚过。
          extendBodyBehindAppBar: true,
          appBar: GlassAppBar(
            title: const Text('我的'),
            actions: [
              if (state.isLoggedIn)
                IconButton(
                  tooltip: '刷新资料',
                  onPressed: state.profileLoading ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            edgeOffset: topInset,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              // 悬浮玻璃底栏浮在页面之上，末尾多留一段，否则最后一项被压住。
              padding: EdgeInsets.fromLTRB(
                16,
                topInset + 6,
                16,
                30 + floatingNavSpace(context),
              ),
              children: [
                if (state.isLoggedIn) ...[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openMySpace,
                    child: _profileHeader(scheme, profile, state.profileLoading),
                  ),
                  const SizedBox(height: 18),
                  // 账号自身的东西排在最前：改资料、看等级、管隐私，这些是
                  // 「我的」页面里唯一点进去只影响自己账号的入口。
                  _menuGroup(scheme, [
                    _MenuItem(Icons.badge_outlined, '资料设置', () {
                      _openPage(const ProfileSettingsPage());
                    }),
                    _MenuItem(Icons.drive_file_rename_outline_rounded, '改名申请', () {
                      _openPage(const RenameRequestPage());
                    }),
                    _MenuItem(Icons.visibility_outlined, '隐私筛选', () {
                      _openPage(const PrivacySettingsPage());
                    }),
                    _MenuItem(Icons.military_tech_outlined, '我的等级', _openMyLevel),
                    _MenuItem(Icons.toll_outlined, '积分', () {
                      _openPage(const CreditPage());
                    }),
                  ]),
                  const SizedBox(height: 14),
                  _menuGroup(scheme, [
                    _MenuItem(Icons.article_outlined, '我的主题', () {
                      _openPersonal('我的主题', 'home.php', {
                        'mod': 'space',
                        'do': 'thread',
                        'view': 'me',
                        'type': 'thread',
                        'from': 'space',
                        'mobile': '2',
                      }, '你还没有发布过主题');
                    }),
                    _MenuItem(Icons.chat_bubble_outline_rounded, '我的回复', () {
                      _openPersonal('我的回复', 'home.php', {
                        'mod': 'space',
                        'do': 'thread',
                        'view': 'me',
                        'type': 'reply',
                        'from': 'space',
                        'mobile': '2',
                      }, '你还没有回复过帖子', replies: true);
                    }),
                    _MenuItem(Icons.star_outline_rounded, '我的收藏', () {
                      _openPersonal('我的收藏', 'home.php', {
                        'mod': 'space',
                        'do': 'favorite',
                        'view': 'me',
                        'mobile': '2',
                      }, '你还没有收藏帖子');
                    }),
                    _MenuItem(Icons.history_rounded, '浏览历史', () {
                      _openPage(const BrowseHistoryPage());
                    }),
                  ]),
                  const SizedBox(height: 14),
                  _menuGroup(scheme, [
                    _MenuItem(Icons.notifications_none_rounded, '消息通知', () {
                      _openPage(const NotificationsPage());
                    }),
                    _MenuItem(Icons.mail_outline_rounded, '私信', () {
                      _openPage(const PmListPage());
                    }),
                    _MenuItem(Icons.group_outlined, '我的好友', () {
                      _openPage(const FriendsPage());
                    }),
                    _MenuItem(Icons.person_add_alt_1_rounded, '我的关注', () {
                      _openPage(const FollowingPage());
                    }),
                    _MenuItem(Icons.people_alt_outlined, '我的粉丝', () {
                      _openPage(const FollowersPage());
                    }),
                    _MenuItem(Icons.gavel_rounded, '小黑屋', () {
                      _openPage(const BlackHousePage());
                    }),
                  ]),
                  const SizedBox(height: 14),
                ] else ...[
                  _loginCard(scheme),
                  const SizedBox(height: 18),
                ],
                _menuGroup(scheme, [
                  _MenuItem(Icons.leaderboard_outlined, '排行榜', () {
                    _openPage(const RankingsPage());
                  }),
                  _MenuItem(Icons.sell_outlined, '标签', () {
                    _openPage(const TagsPage());
                  }),
                  _MenuItem(Icons.download_for_offline_outlined, '下载管理', () {
                    _openPage(const DownloadManagerPage());
                  }),
                  // 未登录时「我的收藏」那一组不可见，这里保留一个入口，
                  // 浏览历史是纯本地数据，游客也该能翻。
                  if (!state.isLoggedIn)
                    _MenuItem(Icons.history_rounded, '浏览历史', () {
                      _openPage(const BrowseHistoryPage());
                    }),
                  _MenuItem(Icons.offline_pin_outlined, '离线缓存', () {
                    _openPage(const OfflineCachePage());
                  }),
                  _MenuItem(Icons.apps_rounded, '更多站点功能', () {
                    _openPage(const SiteFeaturesPage());
                  }),
                  _MenuItem(Icons.smart_toy_outlined, 'MCP 服务', () {
                    _openPage(const McpPage());
                  }),
                ]),
                const SizedBox(height: 14),
                _menuGroup(scheme, [
                  _MenuItem(Icons.public_rounded, '站点', () {
                    _openPage(const SitePickerPage());
                  }),
                  _MenuItem(Icons.palette_outlined, '主题外观', _pickTheme),
                  _MenuItem(Icons.color_lens_outlined, '主题颜色', _pickThemeColor),
                  _MenuItem(Icons.format_color_text_rounded, '阅读配色', () => showReadPaletteSheet(context)),
                  _MenuItem(Icons.blur_on_rounded, '液态玻璃', _pickLiquidGlass),
                  _MenuItem(Icons.info_outline_rounded, '关于本应用', () {
                    Navigator.of(context).push(appRoute(builder: (_) => const AboutPage()));
                  }),
                ]),
                if (state.isLoggedIn) ...[
                  const SizedBox(height: 14),
                  _menuGroup(scheme, [
                    _MenuItem(Icons.key_outlined, '复制 Cookie', _copyCookie),
                    _MenuItem(Icons.logout_rounded, '退出登录', _logout, danger: true),
                  ]),
                ],
                const SizedBox(height: 26),
                Text(
                  'MT论坛 · ${state.isLoggedIn ? '已登录' : '未登录'}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _loginCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.14)),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_rounded, size: 30, color: scheme.primary),
          ),
          const SizedBox(height: 12),
          const Text('登录 MT论坛账号', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(
            '发帖、回复、收藏与查看个人主页',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _openLogin, child: const Text('立即登录')),
        ],
      ),
    );
  }

  Widget _profileHeader(ColorScheme scheme, UserProfile? profile, bool loading) {
    final stats = <(String, String)>[
      ('主题', profile?.posts ?? ''),
      ('回复', profile?.replies ?? ''),
      ('金币', profile?.credits ?? ''),
      ('粉丝', profile?.followers ?? ''),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              UserAvatar(url: profile?.avatar ?? '', name: profile?.username ?? '', size: 58),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.username.isNotEmpty == true ? profile!.username : 'MT论坛用户',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (profile?.group.isNotEmpty == true) _tag(scheme, profile!.group, scheme.primary),
                        if (profile?.level.isNotEmpty == true) _tag(scheme, profile!.level, scheme.tertiary),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (profile != null && profile.uid > 0) 'UID ${profile.uid}',
                        if (profile?.regTime.isNotEmpty == true) '注册于 ${profile!.regTime}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              Icon(Icons.chevron_right_rounded, size: 20, color: scheme.outline),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final stat in stats)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        stat.$2.isEmpty ? '—' : stat.$2,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(stat.$1, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
            ],
          ),
          // 自动签到是静默跑的，不给个位置用户根本不知道今天签没签。
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: SignInBadge(
              signedIn: AppState.instance.signedInToday,
              busy: AppState.instance.signingIn,
              onSignIn: _manualSignIn,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _manualSignIn() async {
    final message = await AppState.instance.signInNow();
    if (!mounted || message == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _tag(ColorScheme scheme, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7)),
        child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
      );

  Widget _menuGroup(ColorScheme scheme, List<_MenuItem> items) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Material(
        // ListTile 的水波纹要画在最近的 Material 上，直接放在带背景色的
        // DecoratedBox 里会被遮住（框架会因此报断言），垫一层透明的就行。
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.45)),
              ListTile(
                leading: Icon(items[i].icon, size: 21, color: items[i].danger ? scheme.error : scheme.onSurfaceVariant),
                title: Text(
                  items[i].label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: items[i].danger ? scheme.error : scheme.onSurface,
                  ),
                ),
                trailing: Icon(Icons.chevron_right_rounded, size: 20, color: scheme.outline),
                onTap: items[i].onTap,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.icon, this.label, this.onTap, {this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

/// 个人主题 / 回复 / 收藏列表。
class _PersonalThreadsPage extends StatelessWidget {
  const _PersonalThreadsPage({
    required this.title,
    required this.path,
    required this.query,
    required this.emptyText,
    this.replies = false,
  });

  final String title;
  final String path;
  final Map<String, String> query;
  final String emptyText;

  /// 回复列表的结构与主题列表不同（链接是 findpost），单独走回复解析。
  final bool replies;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: ThreadFeed(
          loader: (page) => replies
              ? AppState.instance.repo.fetchMyReplies(page: page)
              : AppState.instance.repo.fetchPersonalList(
                  path,
                  query: {...query, 'page': '$page'},
                ),
          emptyText: emptyText,
          padding: glassPagePadding(context, top: 10),
        ),
      ),
    );
  }
}
