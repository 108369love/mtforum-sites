import 'package:in_app_webview_flutter/flutter_inappwebview.dart';

/// 妖火网的会话。
///
/// 站点的所有论坛内容都要登录，而登录页挂着 Cloudflare Turnstile / 阿里云 /
/// EngageLab 三家人机验证——纯 Dart 登录过不去。所以登录交给 WebView 里真实
/// 的浏览器完成，这里只做一件事：把 WebView 的 Cookie 抄出来，给原生请求用。
class YaohuoSession {
  YaohuoSession._();

  static final YaohuoSession instance = YaohuoSession._();

  static const String host = 'yaohuo.me';
  static const String base = 'https://yaohuo.me/';

  Map<String, String> _cookies = <String, String>{};

  /// 抓取最近一次页面时记下的地址，登录页判断用。
  String lastUrl = '';

  String get cookieHeader =>
      _cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');

  bool get hasSession => _cookies.containsKey('ASP.NET_SessionId');

  /// 从 WebView 的 Cookie 仓库同步一次。
  Future<void> refresh() async {
    try {
      final cookies = await CookieManager.instance().getCookies(url: WebUri(base));
      _cookies = <String, String>{
        for (final cookie in cookies)
          if (cookie.name.isNotEmpty) cookie.name: cookie.value,
      };
    } catch (_) {
      // 取不到就沿用上一次的 Cookie，别把已有会话也丢了。
    }
  }

  Future<void> clear() async {
    _cookies = <String, String>{};
  }
}
