import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import 'black_house_page.dart';
import 'credit_page.dart';
import 'login_page.dart';
import 'magic_page.dart';
import 'medals_page.dart';
import 'site_module_page.dart';
import '../navigation/app_routes.dart';
import '../widgets/glass_app_bar.dart';

/// 站点功能导航：全部在 App 内原生呈现，不再跳浏览器。
class SiteFeaturesPage extends StatelessWidget {
  const SiteFeaturesPage({super.key});

  Future<void> _open(BuildContext context, Widget page, {bool needLogin = false}) async {
    if (needLogin && !AppState.instance.isLoggedIn) {
      final ok = await Navigator.of(context).push<bool>(
        noSwipeRoute(builder: (_) => const LoginPage()),
      );
      if (ok != true) return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(appRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = <(String, List<(IconData, String, String, Widget Function(), bool)>)>[
      (
        '社区公示',
        [
          (
            Icons.gavel_rounded,
            '小黑屋',
            '查看被禁言 / 禁止访问的用户',
            () => const BlackHousePage(),
            false,
          ),
        ]
      ),
      (
        '我的账号',
        [
          (
            Icons.military_tech_outlined,
            '勋章中心',
            '勋章目录与获得记录',
            () => const MedalsPage(),
            false,
          ),
          (
            Icons.toll_outlined,
            '积分',
            '积分余额与交易记录',
            () => const CreditPage(),
            true,
          ),
          (
            Icons.auto_fix_high_outlined,
            '道具中心',
            '购买与使用站点道具',
            () => const MagicPage(),
            true,
          ),
        ]
      ),
      (
        '更多',
        [
          (
            Icons.task_alt_rounded,
            '任务中心',
            '站点任务与奖励',
            () => const SiteModulePage(
              title: '任务中心',
              path: 'home.php',
              query: {'mod': 'task', 'mobile': '2'},
              icon: Icons.task_alt_rounded,
            ),
            false,
          ),
          (
            Icons.storefront_outlined,
            '积分商城',
            '用积分兑换会员与道具',
            () => const SiteModulePage(
              title: '积分商城',
              path: 'plugin.php',
              query: {'id': 'keke_integralmall:keke_integralmall', 'mobile': '2'},
              icon: Icons.storefront_outlined,
            ),
            false,
          ),
          (
            Icons.campaign_outlined,
            '访问推广',
            '生成推广链接赚金币',
            () => const SiteModulePage(
              title: '访问推广',
              path: 'home.php',
              query: {'mod': 'spacecp', 'ac': 'promotion', 'mobile': '2'},
              icon: Icons.campaign_outlined,
            ),
            true,
          ),
        ]
      ),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('更多站点功能')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: glassPagePadding(context, top: 12, bottom: 28),
          children: [
            for (final group in groups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: Text(
                  group.$1,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: scheme.outline),
                ),
              ),
              for (final entry in group.$2) ...[
                Material(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _open(context, entry.$4(), needLogin: entry.$5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      child: Row(
                        children: [
                          Icon(entry.$1, size: 22, color: scheme.primary),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  entry.$3,
                                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
