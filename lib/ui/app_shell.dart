import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:ui';

import '../core/sites.dart';
import '../state/app_state.dart';

import 'pages/boards_page.dart';
import 'pages/compose_page.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'pages/search_page.dart';
import 'pages/internal_browser_page.dart';
import 'widgets/glass_compose_button.dart';
import 'widgets/measure_height.dart';
import 'navigation/app_routes.dart';

/// 主框架：底部四栏 + 发帖入口。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  DateTime? _lastBackPressedAt;

  late final List<Widget> _pages = [
    HomePage(onOpenSearch: () => setState(() => _index = 2)),
    const BoardsPage(),
    const SearchPage(),
    const ProfilePage(),
  ];

  Future<void> _openCompose() async {
    await Navigator.of(context)
        .push<bool>(noSwipeRoute(builder: (_) => const ComposePage()));
  }

  void _handleBack(bool didPop) {
    if (didPop) return;
    // 子页面由 Navigator 正常返回；只有根页面拦截系统返回手势。
    if (Navigator.of(context).canPop()) return;
    final now = DateTime.now();
    final last = _lastBackPressedAt;
    if (last != null && now.difference(last) <= const Duration(seconds: 2)) {
      unawaited(SystemNavigator.pop());
      return;
    }
    _lastBackPressedAt = now;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('再按一次返回键退出应用'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // 站点切换要换掉整棵主框架，而 MaterialApp 的 home 是个 const 实例，
    // 父级重建传不下来，所以这里自己对站点选择监听一次。
    return AnimatedBuilder(
      animation: SiteStore.instance,
      builder: (context, _) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final site = SiteStore.instance.current;
    // 站点自带前端（XenForo 这类）：主框架只剩这一个页面，版块/搜索/我的都是
    // Discuz 专用入口，在这里没有意义；切换站点放在它的顶栏菜单里。
    if (site.mode == SiteMode.web) {
      // 站点自带前端：整棵树换成内置浏览器，地址栏/主页/历史/拦截那套都在里面。
      return InternalBrowserPage(
        key: ValueKey('web-site-${site.id}-${site.base}'),
        url: site.homeUrl,
        title: site.name,
        site: site,
      );
    }
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        _handleBack(didPop);
      },
      child: AnimatedBuilder(
        animation: AppState.instance,
        builder: (context, _) => Scaffold(
          extendBody: AppState.instance.floatingGlassNav,
          body: IndexedStack(index: _index, children: _pages),
          floatingActionButton: _index <= 1
              ? GlassComposeButton(onPressed: _openCompose)
              : null,
          bottomNavigationBar: AppState.instance.floatingGlassNav
              ? _buildFloatingGlassNav(context)
              : NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (value) =>
                      setState(() => _index = value),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: '首页',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.grid_view_outlined),
                      selectedIcon: Icon(Icons.grid_view_rounded),
                      label: '版块',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.search_rounded),
                      selectedIcon: Icon(Icons.search_rounded),
                      label: '搜索',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: '我的',
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildFloatingGlassNav(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final glassOpacity = AppState.instance.floatingGlassNavOpacity;
    final glassBlur = AppState.instance.floatingGlassNavBlur;
    const items = [
      (Icons.home_outlined, Icons.home_rounded, '首页'),
      (Icons.grid_view_outlined, Icons.grid_view_rounded, '版块'),
      (Icons.search_rounded, Icons.search_rounded, '搜索'),
      (Icons.person_outline_rounded, Icons.person_rounded, '我的'),
    ];

    // 把底栏真实高度量出来给各页面用：列表末尾要补这么高，最后一张卡片
    // 才不会压进胶囊里（白卡片横穿玻璃，那块看着就像没有玻璃）。
    return MeasureHeight(
      onHeight: AppState.instance.setFloatingNavHeight,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
            child: Container(
              // 描边画在 foregroundDecoration 上：它叠在内容之上，顶部高光、按压反馈都压不住，胶囊边缘才不会出现「中间一段没有线」。
              // 外层补 1.2 的内边距，把描边占的位置还回来，内容不会顶到圆角。
              padding: const EdgeInsets.all(1.2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          const Color(0xFF303945)
                              .withValues(alpha: glassOpacity),
                          const Color(0xFF171D26)
                              .withValues(alpha: glassOpacity * 0.64),
                        ]
                      : [
                          Colors.white.withValues(alpha: glassOpacity),
                          const Color(0xFFF1F5FA)
                              .withValues(alpha: glassOpacity * 0.64),
                        ],
                ),
                // 外侧只留投影。早先还叠了一层 1px 白色内高光，它在浅色下
                // 会把描边洗白成和背景一样，顶边看着就断了。
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                    blurRadius: 30,
                    spreadRadius: 0,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  // 半透明描边叠在白色卡片和浅灰背景上深浅不一，本身就
                  // 「不是一条线」；alpha 提上来，整条边才均匀。
                  color: (isDark ? Colors.white : scheme.outlineVariant)
                      .withValues(alpha: isDark ? 0.18 : 0.55),
                  width: 1.2,
                ),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 5,
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < items.length; i++)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: _index == i,
                              label: items[i].$3,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: () => setState(() => _index = i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 240),
                                  curve: Curves.easeOutCubic,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: _index == i
                                        ? LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              scheme.primary.withValues(
                                                alpha: isDark ? 0.22 : 0.10,
                                              ),
                                              scheme.primary.withValues(
                                                alpha: isDark ? 0.12 : 0.04,
                                              ),
                                            ],
                                          )
                                        : null,
                                    borderRadius: BorderRadius.circular(24),
                                    border: _index == i
                                        ? Border.all(
                                            color: scheme.primary.withValues(
                                              alpha: 0.18,
                                            ),
                                          )
                                        : null,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        child: Icon(
                                          _index == i
                                              ? items[i].$2
                                              : items[i].$1,
                                          key: ValueKey('nav-icon-$i-$_index'),
                                          size: 22,
                                          color: _index == i
                                              ? scheme.primary
                                              : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        items[i].$3,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 11,
                                          height: 1.15,
                                          letterSpacing: 0.1,
                                          fontWeight: _index == i
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: _index == i
                                              ? scheme.primary
                                              : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
