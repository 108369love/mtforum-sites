import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_webview_flutter/flutter_inappwebview.dart';

import '../../../core/app_config.dart';
import '../../../core/yaohuo_session.dart';

/// 妖火登录页。
///
/// 登录接口强制人机验证（Cloudflare Turnstile / 阿里云 / EngageLab），纯 Dart
/// 过不去，所以这里就是一个真实 WebView：验证码由浏览器自己跑完，登录成功后
/// 把 Cookie 抄给 [YaohuoSession]，原生解析层拿着这份 Cookie 去抓页面。
class YaohuoLoginPage extends StatefulWidget {
  const YaohuoLoginPage({super.key});

  @override
  State<YaohuoLoginPage> createState() => _YaohuoLoginPageState();
}

class _YaohuoLoginPageState extends State<YaohuoLoginPage> {
  static const String _loginUrl = 'https://yaohuo.me/waplogin.aspx';

  InAppWebViewController? _controller;
  String _url = _loginUrl;
  int _progress = 0;
  bool _loading = true;
  bool _harvesting = false;

  /// 登录成功后站点会跳到 wapindex；看到这个再收 Cookie。
  bool _looksLoggedIn(String url) => url.contains('wapindex');

  Future<void> _harvest({required bool auto}) async {
    if (_harvesting) return;
    _harvesting = true;
    await YaohuoSession.instance.refresh();
    final ok = YaohuoSession.instance.hasSession;
    _harvesting = false;
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('登录成功，正在读取妖火')));
      Navigator.pop(context, true);
      return;
    }
    if (!auto) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('还没检测到登录态，先完成登录再点确定')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('登录妖火', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(_url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _harvest(auto: false),
            child: const Text('已完成'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100, minHeight: 2),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(_loginUrl),
                headers: {'User-Agent': AppConfig.userAgent},
              ),
              initialSettings: InAppWebViewSettings(
                userAgent: AppConfig.userAgent,
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
                useShouldOverrideUrlLoading: true,
              ),
              onWebViewCreated: (controller) => _controller = controller,
              onProgressChanged: (controller, progress) {
                if (!mounted) return;
                setState(() {
                  _progress = progress;
                  _loading = progress < 100;
                });
              },
              onLoadStop: (controller, url) {
                final current = url?.toString() ?? '';
                if (!mounted) return;
                setState(() {
                  _url = current;
                  _loading = false;
                  _progress = 100;
                });
                if (_looksLoggedIn(current)) {
                  unawaited(_harvest(auto: true));
                }
              },
              shouldOverrideUrlLoading: (controller, action) async {
                final raw = action.request.url?.toString() ?? '';
                if (raw.startsWith('http')) return NavigationActionPolicy.ALLOW;
                return NavigationActionPolicy.CANCEL;
              },
            ),
          ),
        ],
      ),
    );
  }
}
