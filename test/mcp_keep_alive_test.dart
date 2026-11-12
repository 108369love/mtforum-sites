import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/mcp/mcp_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MCP 后台保活：前台服务的拉起、随服务关闭、以及重启后的恢复。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cc.binmt.mt_forum/native');

  /// 原生侧收到的调用，断言用。
  final calls = <MethodCall>[];

  Future<int> freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  setUp(() {
    HttpOverrides.global = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    McpServer.instance.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'mcpKeepAliveStart':
        case 'mcpKeepAliveStop':
        case 'mcpKeepAliveRunning':
        case 'notificationPermission':
        case 'isIgnoringBatteryOptimizations':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    await McpServer.instance.stopForTest();
    McpServer.instance.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('服务运行中打开保活，会拉起前台服务并带上端口', () async {
    final port = await freePort();
    SharedPreferences.setMockInitialValues(<String, Object>{'mt_forum_mcp_port': port});
    await McpServer.instance.load();
    await McpServer.instance.setAllowLan(false);
    await McpServer.instance.setEnabled(true);
    calls.clear();

    await McpServer.instance.setKeepAlive(true);

    expect(McpServer.instance.keepAlive, isTrue);
    expect(McpServer.instance.keepAliveActive, isTrue);
    final start = calls.firstWhere((call) => call.method == 'mcpKeepAliveStart');
    expect((start.arguments as Map)['port'], port);
  });

  test('服务没开时只记住保活偏好，不会挂空通知', () async {
    await McpServer.instance.load();
    calls.clear();

    await McpServer.instance.setKeepAlive(true);

    expect(McpServer.instance.keepAlive, isTrue);
    expect(McpServer.instance.keepAliveActive, isFalse);
    expect(calls.any((call) => call.method == 'mcpKeepAliveStart'), isFalse);
  });

  test('关闭服务时前台服务跟着收掉', () async {
    final port = await freePort();
    SharedPreferences.setMockInitialValues(<String, Object>{'mt_forum_mcp_port': port});
    await McpServer.instance.load();
    await McpServer.instance.setAllowLan(false);
    await McpServer.instance.setEnabled(true);
    await McpServer.instance.setKeepAlive(true);
    calls.clear();

    await McpServer.instance.setEnabled(false);

    expect(McpServer.instance.keepAliveActive, isFalse);
    expect(calls.any((call) => call.method == 'mcpKeepAliveStop'), isTrue);
    // 保活偏好本身保留，下次开服务还会自动拉起。
    expect(McpServer.instance.keepAlive, isTrue);
  });

  test('重启后按上次的配置自动恢复监听和保活', () async {
    final port = await freePort();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mt_forum_mcp_port': port,
      'mt_forum_mcp_enabled': true,
      'mt_forum_mcp_keep_alive': true,
    });

    await McpServer.instance.load();

    expect(McpServer.instance.running, isTrue);
    expect(McpServer.instance.keepAlive, isTrue);
    expect(McpServer.instance.keepAliveActive, isTrue);
    expect(calls.any((call) => call.method == 'mcpKeepAliveStart'), isTrue);
  });

  test('保活开关会写进本地配置', () async {
    await McpServer.instance.load();
    await McpServer.instance.setKeepAlive(true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('mt_forum_mcp_keep_alive'), isTrue);
  });

  test('监听被后台收掉后，回到前台能自己补回来', () async {
    final port = await freePort();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mt_forum_mcp_port': port,
      'mt_forum_mcp_enabled': true,
      'mt_forum_mcp_keep_alive': true,
    });
    await McpServer.instance.load();
    expect(McpServer.instance.running, isTrue);

    // 模拟后台被系统冻结/回收：socket 已经没了，但开关还停在「开着」。
    await McpServer.instance.stop();
    expect(McpServer.instance.running, isFalse);
    calls.clear();

    await McpServer.instance.syncKeepAlive();

    expect(McpServer.instance.running, isTrue, reason: '回到前台要自己把监听重新绑上');
    expect(McpServer.instance.keepAliveActive, isTrue);
    expect(calls.any((call) => call.method == 'mcpKeepAliveStart'), isTrue);
  });
}
