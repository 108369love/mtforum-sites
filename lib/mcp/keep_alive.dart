import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// MCP 后台保活的原生桥。
///
/// Android 侧是一个空壳前台服务（[McpKeepAliveService]），不跑业务，只负责
/// 把宿主进程按住 —— App 退到后台或锁屏后，系统不会因为「后台无活动」把进程
/// 回收或冻结，Dart 里的 HttpServer 才能一直听端口。其他平台直接当不支持。
class McpKeepAlive {
  const McpKeepAlive._();

  static const MethodChannel _channel = MethodChannel('cc.binmt.mt_forum/native');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 启动前台服务；已经在跑时调用相当于更新通知里的端口。
  static Future<bool> start({required int port}) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('mcpKeepAliveStart', {'port': port}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> stop() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('mcpKeepAliveStop') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 前台服务此刻是否真的在跑（App 重启后 Dart 侧没有状态，只能问系统）。
  static Future<bool> isRunning() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('mcpKeepAliveRunning') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Android 13 起通知要用户授权；没授权服务照样跑，只是通知栏看不见。
  static Future<bool> hasNotificationPermission() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('notificationPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestNotificationPermission() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestNotificationPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 是否已经进了电池优化白名单。
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 拉起系统的「忽略电池优化」确认框。结果要等用户操作，这里不等待。
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } catch (_) {
      // 系统页面拉不起来也不影响主流程。
    }
  }
}
