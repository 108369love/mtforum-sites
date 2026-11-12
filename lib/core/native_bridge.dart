import 'package:flutter/services.dart';

/// 原生能力桥：系统分享、图片保存到相册。
class NativeBridge {
  const NativeBridge._();

  static const MethodChannel _channel = MethodChannel('cc.binmt.mt_forum/native');

  static Future<bool> shareText(String text) async {
    try {
      await _channel.invokeMethod<bool>('shareText', {'text': text});
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> saveImage(Uint8List bytes, {String name = 'mt_forum.jpg'}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('saveImage', {
        'bytes': bytes,
        'name': name,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
