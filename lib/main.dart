import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_config.dart';
import 'core/app_theme.dart';
import 'core/sites.dart';
import 'mcp/mcp_server.dart';
import 'state/app_state.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await AppState.instance.bootstrapLocal();
  } catch (_) {
    // 本地缓存初始化失败也应进入应用。
  }
  // 上次选的站点要在首帧之前定下来：站点决定主框架长什么样，先渲染再纠正会闪一下。
  await SiteStore.instance.load();
  // 上次开着 MCP 服务的话，开机自动恢复监听；关着就只读一下配置。
  unawaited(McpServer.instance.load());
  runApp(const MtForumApp());
  // 首帧之后 Activity 才把原生通道挂上，这时补一次保活对齐——
  // main 里那一次 start 可能因为通道还没就绪而静默失败。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(McpServer.instance.syncKeepAlive());
  });
}

class MtForumApp extends StatefulWidget {
  const MtForumApp({super.key});

  @override
  State<MtForumApp> createState() => _MtForumAppState();
}

class _MtForumAppState extends State<MtForumApp> with WidgetsBindingObserver {
  /// 主题和站点两路通知合成一路：两者都会换掉整棵树，分开监听只会重建两次。
  static final Listenable _sources = Listenable.merge([AppState.instance, SiteStore.instance]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 回到前台补一次对齐：后台期间监听可能被系统收掉、前台服务也可能被杀过，
  /// 这时界面上还写着「运行中」，实际已经连不上。重建比等用户重开页面靠谱。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(McpServer.instance.syncKeepAlive());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sources,
      builder: (context, _) => MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(AppState.instance.themeSeedColor),
        darkTheme: AppTheme.dark(AppState.instance.themeSeedColor),
        themeMode: AppState.instance.themeMode,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const AppShell(),
      ),
    );
  }
}
