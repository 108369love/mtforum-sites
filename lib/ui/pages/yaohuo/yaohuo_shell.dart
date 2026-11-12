import 'package:flutter/material.dart';

import 'yaohuo_home_page.dart';
import 'yaohuo_profile_page.dart';
import 'yaohuo_hot_page.dart';

/// 妖火的原生主框架：和 MT论坛 一样四栏（首页 / 版块 / 搜索 / 我的）。
class YaohuoShell extends StatefulWidget {
  const YaohuoShell({super.key});

  @override
  State<YaohuoShell> createState() => _YaohuoShellState();
}

class _YaohuoShellState extends State<YaohuoShell> {
  int _index = 0;

  late final List<Widget> _pages = <Widget>[
    const YaohuoHomePage(),
    const YaohuoBoardsPage(),
    const YaohuoHotPage(),
    const YaohuoProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const <NavigationDestination>[
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
            icon: Icon(Icons.local_fire_department_outlined),
            selectedIcon: Icon(Icons.local_fire_department_rounded),
            label: '热门',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
