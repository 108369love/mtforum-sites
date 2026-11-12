import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'keep_alive.dart';
import 'mcp_tools.dart';

/// 一条工具调用记录，给控制台看。
class McpLogEntry {
  McpLogEntry({
    required this.at,
    required this.name,
    required this.title,
    required this.ok,
    required this.ms,
    this.detail = '',
  });

  final DateTime at;
  final String name;
  final String title;
  final bool ok;
  final int ms;
  final String detail;
}

/// App 内置的 MCP 服务。
///
/// 手机和电脑连同一个 Wi-Fi 时，电脑上的 AI 客户端（Claude Desktop、Cursor、
/// Cherry Studio 等）可以通过 Streamable HTTP 连到本机，直接调用论坛能力。
/// 鉴权靠一串本地生成的 token；登录态复用 App 自己的 [HttpSession]，
/// 所以调用方不需要再提供账号密码。
class McpServer extends ChangeNotifier {
  McpServer._();

  static final McpServer instance = McpServer._();

  static const String _keyEnabled = 'mt_forum_mcp_enabled';
  static const String _keyLan = 'mt_forum_mcp_lan';
  static const String _keyPort = 'mt_forum_mcp_port';
  static const String _keyToken = 'mt_forum_mcp_token';
  static const String _keyWrite = 'mt_forum_mcp_write';
  static const String _keyRequireToken = 'mt_forum_mcp_require_token';
  static const String _keyKeepAlive = 'mt_forum_mcp_keep_alive';

  static const String serverName = 'mtforum';
  static const String serverVersion = '1.0.0';

  /// 声明支持的最新协议版本；客户端请求更老的就回它自己那版。
  static const String _protocolVersion = '2025-06-18';
  static const Set<String> _knownVersions = <String>{
    '2024-11-05',
    '2025-03-26',
    '2025-06-18',
  };

  final McpTools _tools = McpTools();

  HttpServer? _server;
  bool _enabled = false;
  bool _loaded = false;
  bool allowLan = true;
  bool allowWrite = true;

  /// 是否校验令牌。关掉之后同一网络里任何客户端都能直接调用，
  /// 适合临时用本机调试；默认开着。
  bool requireToken = true;

  /// 后台保活：开一个前台服务把进程按住，切后台 / 锁屏后仍能被连上。
  bool keepAlive = false;

  /// 前台服务是否确实在跑（真机确认过，不是只读了配置）。
  bool keepAliveActive = false;

  int port = 8642;
  String token = '';

  /// 局域网地址，启动时异步刷新一次。
  List<String> lanAddresses = const <String>[];

  final List<McpLogEntry> logs = <McpLogEntry>[];

  int calls = 0;
  int errors = 0;
  String? lastError;

  bool get running => _server != null;
  bool get enabled => _enabled;
  bool get loaded => _loaded;

  /// 客户端要填的地址。第一个一定是本机回环。
  List<String> get urls => <String>[
        'http://127.0.0.1:$port/mcp',
        if (allowLan)
          for (final address in lanAddresses) 'http://$address:$port/mcp',
      ];

  DateTime? _startedAt;

  DateTime? get startedAt => _startedAt;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_keyEnabled) ?? false;
    allowLan = prefs.getBool(_keyLan) ?? true;
    allowWrite = prefs.getBool(_keyWrite) ?? true;
    requireToken = prefs.getBool(_keyRequireToken) ?? true;
    keepAlive = prefs.getBool(_keyKeepAlive) ?? false;
    port = prefs.getInt(_keyPort) ?? 8642;
    token = prefs.getString(_keyToken) ?? '';
    if (token.isEmpty) {
      token = _newToken();
      await prefs.setString(_keyToken, token);
    }
    _loaded = true;
    notifyListeners();
    if (_enabled) await start();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    await _persist();
    if (value) {
      await start();
    } else {
      await stop();
    }
    notifyListeners();
  }

  Future<void> setPort(int value) async {
    final next = value.clamp(1024, 65535);
    if (next == port) return;
    port = next;
    await _persist();
    if (running) {
      await stop();
      await start();
    }
    notifyListeners();
  }

  Future<void> setAllowLan(bool value) async {
    if (allowLan == value) return;
    allowLan = value;
    await _persist();
    if (running) {
      await stop();
      await start();
    }
    notifyListeners();
  }

  Future<void> setAllowWrite(bool value) async {
    if (allowWrite == value) return;
    allowWrite = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setRequireToken(bool value) async {
    if (requireToken == value) return;
    requireToken = value;
    await _persist();
    notifyListeners();
  }

  /// 开关后台保活。服务没在跑时只记住偏好，等下次 [start] 再拉起前台服务。
  Future<void> setKeepAlive(bool value) async {
    if (keepAlive == value) return;
    keepAlive = value;
    await _persist();
    notifyListeners();
    await _syncKeepAlive();
  }

  /// App 回到前台时对齐一次保活状态。
  ///
  /// 两件事：监听可能在后台被系统悄悄收掉（进程被冻结后 socket 半死、
  /// 或者服务被 ROM 杀过一次），先按配置重建；再把前台服务拉起来。
  /// 只在 [load] 之后、确实开着服务的时候动手，避免把用户关掉的开关又打开。
  Future<void> syncKeepAlive() async {
    if (!_loaded) return;
    if (_enabled && !running) await start();
    await _syncKeepAlive();
  }

  Future<void> _syncKeepAlive() async {
    if (keepAlive && running) {
      final ok = await McpKeepAlive.start(port: port);
      if (ok != keepAliveActive) {
        keepAliveActive = ok;
        notifyListeners();
      }
    } else {
      // 服务没开或者用户关了保活，都不该继续挂一条「运行中」的通知。
      await McpKeepAlive.stop();
      if (keepAliveActive) {
        keepAliveActive = false;
        notifyListeners();
      }
    }
  }

  Future<String> regenerateToken() async {
    token = _newToken();
    await _persist();
    notifyListeners();
    return token;
  }

  Future<void> start() async {
    if (_server != null) return;
    lastError = null;
    try {
      final address = allowLan ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4;
      final server = await HttpServer.bind(address, port);
      _server = server;
      _startedAt = DateTime.now();
      server.listen(
        _handle,
        onError: (Object error) {
          lastError = '监听出错：$error';
          notifyListeners();
        },
      );
      unawaited(_refreshAddresses());
    } on SocketException catch (error) {
      lastError = '端口 $port 无法监听：${error.osError?.message ?? error.message}';
      _enabled = false;
      await _persist();
    } catch (error) {
      lastError = '启动失败：$error';
      _enabled = false;
      await _persist();
    }
    notifyListeners();
    if (_server != null) await _syncKeepAlive();
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _startedAt = null;
    if (server != null) {
      await server.close(force: true);
    }
    if (keepAliveActive) {
      await McpKeepAlive.stop();
      keepAliveActive = false;
    }
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    calls = 0;
    errors = 0;
    notifyListeners();
  }

  // ------------------------------------------------------------ HTTP 层

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set(
      'Access-Control-Allow-Headers',
      'authorization, content-type, accept, mcp-session-id, x-mcp-token',
    );
    response.headers.set('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      await response.close();
      return;
    }

    final path = request.uri.path.replaceAll(RegExp(r'/+$'), '');

    // 根路径给一个纯文本状态页，方便用浏览器确认「手机确实在服务」。
    if (path.isEmpty && request.method == 'GET') {
      response.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
      response.write('MT论坛 MCP 服务\n'
          'endpoint: /mcp\n'
          'protocol: $_protocolVersion\n'
          'tools: ${_tools.all.length}\n'
          '需要 Authorization: Bearer <App 内显示的 token>\n');
      await response.close();
      return;
    }

    if (path != '/mcp') {
      await _sendJson(response, HttpStatus.notFound, <String, Object?>{
        'error': 'not_found',
        'message': 'MCP 端点是 /mcp',
      });
      return;
    }

    if (!_authorized(request)) {
      await _sendJson(response, HttpStatus.unauthorized, <String, Object?>{
        'error': 'unauthorized',
        'message': 'token 无效，请在 App 的 MCP 服务页复制最新 token',
      });
      return;
    }

    // 只做 Streamable HTTP 的 POST 模式：GET（SSE 长连接）不提供服务。
    if (request.method != 'POST') {
      response.statusCode = HttpStatus.methodNotAllowed;
      response.headers.set('Allow', 'POST');
      await _sendJson(response, HttpStatus.methodNotAllowed, <String, Object?>{
        'error': 'method_not_allowed',
      });
      return;
    }

    String body;
    try {
      body = await utf8.decodeStream(request);
    } catch (error) {
      await _sendJson(response, HttpStatus.badRequest, _rpcError(null, -32700, '读取请求失败：$error'));
      return;
    }

    Object? payload;
    try {
      payload = jsonDecode(body);
    } catch (error) {
      await _sendJson(response, HttpStatus.ok, _rpcError(null, -32700, 'JSON 解析失败：$error'));
      return;
    }

    if (payload is List) {
      final responses = <Object?>[];
      for (final item in payload) {
        if (item is! Map) {
          responses.add(_rpcError(null, -32600, '请求项必须是对象'));
          continue;
        }
        final result = await _dispatch(Map<String, dynamic>.from(item));
        if (result != null) responses.add(result);
      }
      if (responses.isEmpty) {
        response.statusCode = HttpStatus.accepted;
        await response.close();
        return;
      }
      await _sendJson(response, HttpStatus.ok, responses);
      return;
    }

    if (payload is! Map) {
      await _sendJson(response, HttpStatus.ok, _rpcError(null, -32600, '请求必须是对象或数组'));
      return;
    }

    final message = Map<String, dynamic>.from(payload);
    final result = await _dispatch(message);
    if (result == null) {
      // 通知类消息没有响应体，规范要求 202。
      response.statusCode = HttpStatus.accepted;
      await response.close();
      return;
    }
    response.headers.set('Mcp-Session-Id', _sessionId);
    await _sendJson(response, HttpStatus.ok, result);
  }

  bool _authorized(HttpRequest request) {
    // 手动关掉令牌校验后不再看请求头，谁连上谁就能用。
    if (!requireToken) return true;
    if (token.isEmpty) return false;
    final header = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    if (header.toLowerCase().startsWith('bearer ')) {
      if (header.substring(7).trim() == token) return true;
    }
    if (request.headers.value('x-mcp-token') == token) return true;
    if (request.uri.queryParameters['token'] == token) return true;
    return false;
  }

  final String _sessionId = _newToken();

  // ------------------------------------------------------------ JSON-RPC

  Future<Map<String, dynamic>?> _dispatch(Map<String, dynamic> message) async {
    final id = message['id'];
    final method = '${message['method'] ?? ''}';
    final isNotification = !message.containsKey('id');

    switch (method) {
      case 'initialize':
        final params = message['params'];
        final requested = params is Map ? '${params['protocolVersion'] ?? ''}' : '';
        final version = _knownVersions.contains(requested) ? requested : _protocolVersion;
        return _rpcOk(id, <String, Object?>{
          'protocolVersion': version,
          'capabilities': <String, Object?>{
            'tools': <String, Object?>{'listChanged': false},
          },
          'serverInfo': <String, Object?>{
            'name': serverName,
            'title': 'MT论坛',
            'version': serverVersion,
          },
          'instructions': '这是 MT论坛 的手机客户端。所有工具都使用 App 内已登录的账号，'
              '权限与该账号一致。先用 forum_list_boards 找版块，再发帖或回复。'
              '读长帖可以用 forum_get_thread 的 format=markdown 保留代码块与引用，'
              '只要某一楼用 forum_get_post；forum_list_notices 读提醒，'
              'forum_favorite 收藏，forum_edit_post 会先返回原文、再提交改写。',
        });

      case 'notifications/initialized':
      case 'notifications/cancelled':
      case 'notifications/roots/list_changed':
        return null;

      case 'ping':
        return _rpcOk(id, <String, Object?>{});

      case 'tools/list':
        return _rpcOk(id, <String, Object?>{
          'tools': <Object?>[for (final tool in _tools.all) tool.describe()],
        });

      case 'tools/call':
        return _callTool(id, message['params']);

      case 'resources/list':
        return _rpcOk(id, <String, Object?>{'resources': const <Object?>[]});

      case 'prompts/list':
        return _rpcOk(id, <String, Object?>{'prompts': const <Object?>[]});

      default:
        if (isNotification) return null;
        return _rpcError(id, -32601, '不支持的方法：$method');
    }
  }

  Future<Map<String, dynamic>> _callTool(Object? id, Object? rawParams) async {
    if (rawParams is! Map) {
      return _rpcError(id, -32602, 'params 必须是对象');
    }
    final name = '${rawParams['name'] ?? ''}';
    final tool = _tools.byName(name);
    if (tool == null) {
      return _rpcError(id, -32602, '未知工具：$name');
    }

    final rawArgs = rawParams['arguments'];
    final args = rawArgs is Map
        ? Map<String, dynamic>.from(rawArgs)
        : <String, dynamic>{};

    if (tool.write && !allowWrite) {
      return _rpcOk(id, _toolResult('写操作已在 App 的 MCP 服务页关闭，只能读不能发。', isError: true));
    }

    final started = DateTime.now();
    try {
      final result = await tool.run(args).timeout(const Duration(seconds: 60));
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      _record(McpLogEntry(
        at: started,
        name: tool.name,
        title: tool.title,
        ok: true,
        ms: elapsed,
        detail: _brief(args),
      ));
      return _rpcOk(id, _toolResult(_stringify(result), isError: false));
    } catch (error) {
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      _record(McpLogEntry(
        at: started,
        name: tool.name,
        title: tool.title,
        ok: false,
        ms: elapsed,
        detail: '$error',
      ));
      return _rpcOk(id, _toolResult('$error', isError: true));
    }
  }

  Map<String, Object?> _toolResult(String text, {required bool isError}) =>
      <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': text},
        ],
        'isError': isError,
      };

  String _stringify(Object? result) {
    if (result == null) return 'ok';
    if (result is String) return result;
    return const JsonEncoder.withIndent('  ').convert(result);
  }

  String _brief(Map<String, dynamic> args) {
    if (args.isEmpty) return '';
    final text = args.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ')
        .replaceAll('\n', ' ');
    return text.length <= 120 ? text : '${text.substring(0, 120)}…';
  }

  void _record(McpLogEntry entry) {
    logs.insert(0, entry);
    if (logs.length > 120) logs.removeLast();
    calls++;
    if (!entry.ok) errors++;
    notifyListeners();
  }

  // ------------------------------------------------------------ 辅助

  Future<void> _sendJson(HttpResponse response, int status, Object? body) async {
    response.statusCode = status;
    response.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    response.write(jsonEncode(body));
    await response.close();
  }

  Map<String, Object?> _rpcOk(Object? id, Object? result) => <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      };

  Map<String, Object?> _rpcError(Object? id, int code, String message) => <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{'code': code, 'message': message},
      };

  Future<void> _refreshAddresses() async {
    final found = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.isLoopback) continue;
          found.add(address.address);
        }
      }
    } catch (_) {
      // 拿不到网卡不影响服务本身，只是地址列表可能为空。
    }
    lanAddresses = found;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, _enabled);
    await prefs.setBool(_keyLan, allowLan);
    await prefs.setBool(_keyWrite, allowWrite);
    await prefs.setBool(_keyRequireToken, requireToken);
    await prefs.setBool(_keyKeepAlive, keepAlive);
    await prefs.setInt(_keyPort, port);
    await prefs.setString(_keyToken, token);
  }

  static String _newToken() {
    final random = Random.secure();
    return List<String>.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// 测试用：把单例恢复到刚安装的状态。
  @visibleForTesting
  void resetForTest() {
    logs.clear();
    calls = 0;
    errors = 0;
    lastError = null;
    lanAddresses = const <String>[];
    allowWrite = true;
    requireToken = true;
    allowLan = false;
    port = 8642;
    token = '';
    _enabled = false;
    _loaded = false;
    _startedAt = null;
    keepAlive = false;
    keepAliveActive = false;
  }

  /// 测试用：直接喂一条 JSON-RPC 消息，绕开 HTTP 层。
  @visibleForTesting
  Future<Map<String, dynamic>?> dispatchForTest(Map<String, dynamic> message) =>
      _dispatch(message);

  @visibleForTesting
  Future<void> stopForTest() => stop();
}
