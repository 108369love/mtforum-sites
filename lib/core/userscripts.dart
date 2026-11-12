import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一条用户脚本（油猴脚本）。
///
/// 只保留真正用得上的部分：元数据里的 `@name` / `@match`，源码，和一个开关。
/// `@run-at` 目前固定按 `document-idle` 处理（页面加载完成后再注入），
/// `@grant` 由内置的 GM 垫片覆盖 `GM_xmlhttpRequest` 这一项。
class UserScript {
  UserScript({
    required this.id,
    required this.name,
    required this.matches,
    required this.code,
    this.enabled = true,
    this.installedAt = 0,
  });

  final String id;
  final String name;
  final List<String> matches;
  final String code;
  bool enabled;
  final int installedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'matches': matches,
        'code': code,
        'enabled': enabled,
        'ts': installedAt,
      };

  static UserScript? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final code = raw['code'];
    if (id is! String || code is! String) return null;
    final matchesRaw = raw['matches'];
    final matches = matchesRaw is List ? matchesRaw.whereType<String>().toList() : <String>[];
    return UserScript(
      id: id,
      name: raw['name'] is String && (raw['name'] as String).isNotEmpty ? raw['name'] as String : '未命名脚本',
      matches: matches,
      code: code,
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : true,
      installedAt: raw['ts'] is int ? raw['ts'] as int : 0,
    );
  }
}

/// 用户脚本的存取与匹配。
class UserScriptStore extends ChangeNotifier {
  UserScriptStore._();

  static final UserScriptStore instance = UserScriptStore._();

  static const String _key = 'mt_forum_userscripts';

  List<UserScript> _scripts = <UserScript>[];

  List<UserScript> get scripts => List<UserScript>.unmodifiable(_scripts);

  bool get anyEnabled => _scripts.any((script) => script.enabled);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw);
      if (data is! List) return;
      final scripts = data.map(UserScript.fromJson).whereType<UserScript>().toList();
      _scripts = scripts;
      notifyListeners();
    } catch (_) {
      // 解析失败就当没装过脚本，不影响浏览器本身。
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_scripts.map((s) => s.toJson()).toList()));
    } catch (_) {
      // 存不下就只在本次会话里生效。
    }
  }

  /// 从脚本源码里读 `@name` / `@match`。
  static ({String name, List<String> matches}) parseMeta(String code) {
    var name = '';
    final matches = <String>[];
    for (final line in const LineSplitter().convert(code)) {
      final text = line.trim();
      if (!text.startsWith('//')) continue;
      final body = text.substring(2).trim();
      if (body.startsWith('@name') && name.isEmpty) {
        name = body.substring(5).trim();
      } else if (body.startsWith('@match')) {
        final pattern = body.substring(6).trim();
        if (pattern.isNotEmpty) matches.add(pattern);
      }
    }
    if (matches.isEmpty) matches.add('*://*/*');
    return (name: name, matches: matches);
  }

  /// 导入脚本；同名脚本会被覆盖（当作升级）。
  Future<({bool ok, String message, UserScript? script})> import(String code) async {
    final text = code.trim();
    if (!text.contains('==UserScript==')) {
      return (ok: false, message: '这不是油猴脚本：缺少 ==UserScript== 头', script: null);
    }
    final meta = parseMeta(text);
    final script = UserScript(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: meta.name.isEmpty ? '未命名脚本' : meta.name,
      matches: meta.matches,
      code: text,
      installedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final existing = _scripts.indexWhere((s) => s.name == script.name);
    if (existing >= 0) {
      _scripts[existing] = script;
    } else {
      _scripts.add(script);
    }
    notifyListeners();
    await _persist();
    return (
      ok: true,
      message: existing >= 0 ? '已更新 ${script.name}' : '已安装 ${script.name}',
      script: script,
    );
  }

  Future<void> remove(String id) async {
    _scripts.removeWhere((script) => script.id == id);
    notifyListeners();
    await _persist();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final index = _scripts.indexWhere((script) => script.id == id);
    if (index < 0) return;
    _scripts[index].enabled = enabled;
    notifyListeners();
    await _persist();
  }

  Future<void> setAllEnabled(bool enabled) async {
    for (final script in _scripts) {
      script.enabled = enabled;
    }
    notifyListeners();
    await _persist();
  }

  /// 当前地址命中的、且开着开关的脚本。
  List<UserScript> matching(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return <UserScript>[];
    return _scripts.where((script) => script.enabled && script.matches.any((p) => _matches(p, uri))).toList();
  }

  bool _matches(String pattern, Uri url) {
    if (pattern == '<all_urls>') return true;
    try {
      final escaped = RegExp.escape(pattern).replaceAll(r'\*', '.*');
      return RegExp('^$escaped\$').hasMatch(url.toString());
    } catch (_) {
      return false;
    }
  }

  /// 注入脚本前先铺的 GM 垫片。
  ///
  /// 翻译类脚本真正依赖的只有 `GM_xmlhttpRequest`（跨域抓翻译接口），所以这里
  /// 只实现它，外加 `GM_addStyle` / `GM_log` 两个零成本的老 API。请求转发给
  /// Dart 侧用原生 HTTP 发，天然没有 CORS 限制。
  static const String prelude = r'''
(function () {
  if (window.GM_xmlhttpRequest) return;
  function request(details) {
    var d = details || {};
    var aborted = false;
    var payload = {
      url: d.url || '',
      method: d.method || 'GET',
      headers: d.headers || {},
      data: d.data === undefined ? null : String(d.data)
    };
    try {
      window.flutter_inappwebview.callHandler('gmXhr', payload).then(function (res) {
        if (aborted) return;
        try {
          if (!res || res.error) { if (d.onerror) d.onerror(res || { error: 'request failed' }); return; }
          if (d.onreadystatechange) d.onreadystatechange(res);
          if (d.onload) d.onload(res);
        } catch (e) {}
      }).catch(function (err) {
        if (!aborted && d.onerror) d.onerror({ error: String(err) });
      });
    } catch (e) {
      if (d.onerror) d.onerror({ error: String(e) });
    }
    return { abort: function () { aborted = true; } };
  }
  window.GM_xmlhttpRequest = request;
  window.GM = window.GM || {};
  window.GM.xmlHttpRequest = request;
  if (!window.GM_addStyle) {
    window.GM_addStyle = function (css) {
      var style = document.createElement('style');
      style.textContent = css;
      (document.head || document.documentElement).appendChild(style);
      return style;
    };
  }
  if (!window.GM_log) {
    window.GM_log = function () { try { console.log.apply(console, arguments); } catch (e) {} };
  }
})();
''';
}
