import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'waf_solver.dart';

class SiteException implements Exception {
  SiteException(this.message, {this.code});
  final String message;
  final int? code;

  @override
  String toString() => message;
}

class HttpResult {
  HttpResult(this.statusCode, this.body, this.uri, this.headers);

  final int statusCode;
  final String body;
  final Uri uri;
  final Map<String, String> headers;

  bool get ok => statusCode >= 200 && statusCode < 400;
}

/// multipart/form-data 上传负载。
class HttpUpload {
  const HttpUpload({
    required this.field,
    required this.filename,
    required this.bytes,
    this.fields = const {},
    this.extraFiles = const [],
  });

  final String field;
  final String filename;
  final List<int> bytes;
  final Map<String, String> fields;

  /// 同一个字段名下的其它文件，多图一起提交时用（Discuz 表单里就是多个
  /// `<input type="file" name="Filedata">`，字段名重复出现）。
  final List<HttpUploadFile> extraFiles;

  Iterable<HttpUploadFile> get allFiles => [
    HttpUploadFile(filename: filename, bytes: bytes),
    ...extraFiles,
  ];
}

class HttpUploadFile {
  const HttpUploadFile({required this.filename, required this.bytes});

  final String filename;
  final List<int> bytes;
}

/// 带 Cookie、重定向、gzip 与 WAF 自动处理的 HTTP 会话。
class HttpSession {
  HttpSession._();

  static final HttpSession instance = HttpSession._();

  static const Duration _timeout = Duration(seconds: 20);
  static const String _cookieKey = 'mt_forum_cookies_v1';

  final http.Client _client = http.Client();
  final Map<String, String> _cookies = <String, String>{};
  SharedPreferences? _prefs;

  static const Set<String> _attributes = {
    'expires', 'path', 'domain', 'max-age', 'httponly', 'secure',
    'samesite', 'priority', 'version', 'comment', 'partitioned',
  };

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_cookieKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _cookies
        ..clear()
        ..addAll(map.map((key, value) => MapEntry(key, '$value')));
    } catch (_) {
      // 忽略损坏的缓存。
    }
  }

  void _saveCookies() {
    _prefs?.setString(_cookieKey, jsonEncode(_cookies));
  }

  bool get hasLoginCookie =>
      _cookies.keys.any((key) => key.toLowerCase().endsWith('_auth') && _cookies[key]!.isNotEmpty);

  String get cookieHeader => _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// Cookie 条数，给「复制 Cookie」页面显示用。
  int get cookieCount => _cookies.length;

  /// 按名字排序的 Cookie 名，只读快照。
  List<String> get cookieNames => _cookies.keys.toList()..sort();

  String? cookie(String name) => _cookies[name];

  void clear() {
    _cookies.clear();
    _saveCookies();
  }

  void setCookie(String name, String value) {
    _cookies[name] = value;
    _saveCookies();
  }

  void removeCookie(String name) {
    _cookies.remove(name);
    _saveCookies();
  }

  void _absorbCookies(Iterable<String> values) {
    var changed = false;
    for (final header in values) {
      for (final match in RegExp(r'([A-Za-z0-9_\-]+)=([^;,\s]+)').allMatches(header)) {
        final name = match.group(1)!;
        final value = match.group(2)!;
        if (_attributes.contains(name.toLowerCase())) continue;
        if (value == 'deleted') {
          changed = _cookies.remove(name) != null || changed;
        } else {
          _cookies[name] = value;
          changed = true;
        }
      }
    }
    if (changed) _saveCookies();
  }

  Map<String, String> _headers({String? referer, String? userAgent}) => {
        'User-Agent': userAgent ?? AppConfig.userAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.6',
        'Accept-Encoding': 'gzip',
        'Cache-Control': 'no-cache',
        'Referer': referer ?? AppConfig.base,
        if (_cookies.isNotEmpty) 'Cookie': cookieHeader,
      };

  Future<HttpResult> get(
    String url, {
    Map<String, String>? query,
    String? referer,
    String? userAgent,
    bool retryWaf = true,
  }) =>
      _request('GET', AppConfig.uri(url, query), referer: referer, userAgent: userAgent, retryWaf: retryWaf);

  Future<HttpResult> post(
    String url, {
    Map<String, String>? form,
    Map<String, String>? query,
    String? referer,
    String? userAgent,
  }) =>
      _request('POST', AppConfig.uri(url, query), form: form, referer: referer, userAgent: userAgent);

  /// 上传单个文件（multipart/form-data），用于论坛附件与图片。
  Future<HttpResult> postFile(
    String url, {
    required String field,
    required String filename,
    required List<int> bytes,
    List<HttpUploadFile> extraFiles = const [],
    Map<String, String>? fields,
    Map<String, String>? query,
    String? referer,
  }) =>
      _request(
        'POST',
        AppConfig.uri(url, query),
        upload: HttpUpload(
          field: field,
          filename: filename,
          bytes: bytes,
          fields: fields ?? const {},
          extraFiles: extraFiles,
        ),
        referer: referer,
      );

  Future<HttpResult> _request(
    String method,
    Uri uri, {
    Map<String, String>? form,
    HttpUpload? upload,
    String? referer,
    String? userAgent,
    bool retryWaf = true,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final result = await _send(method, uri, form: form, upload: upload, referer: referer, userAgent: userAgent);
        if (WafSolver.isChallenge(result.body)) {
          final cookie = WafSolver.solve(result.body);
          if (cookie != null && cookie.isNotEmpty) {
            setCookie('acw_sc__v2', cookie);
            continue;
          }
          throw SiteException('站点安全校验失败，请稍后重试', code: result.statusCode);
        }
        if (result.statusCode == 403 && result.body.trim().isEmpty) {
          if (attempt < 2) {
            await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
            continue;
          }
          throw SiteException('访问被站点暂时限制，请稍后再试', code: 403);
        }
        return result;
      } on SiteException {
        rethrow;
      } on TimeoutException {
        if (attempt == 2) throw SiteException('网络连接超时，请检查网络后重试');
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      } on SocketException {
        if (attempt == 2) throw SiteException('网络不可用，请检查网络连接');
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      } on http.ClientException {
        if (attempt == 2) throw SiteException('网络请求失败，请稍后重试');
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    throw SiteException('访问站点失败，请稍后重试');
  }

  Future<HttpResult> _send(
    String method,
    Uri uri, {
    Map<String, String>? form,
    HttpUpload? upload,
    String? referer,
    String? userAgent,
  }) async {
    var currentMethod = method;
    var currentUri = uri;
    var currentForm = form;
    var currentUpload = upload;

    for (var hop = 0; hop < 6; hop++) {
      final requestHeaders = _headers(referer: referer, userAgent: userAgent);
      final http.BaseRequest request;
      if (currentUpload != null && currentMethod.toUpperCase() == 'POST') {
        final multipart = http.MultipartRequest(currentMethod, currentUri);
        multipart.headers.addAll(requestHeaders);
        multipart.fields.addAll(currentUpload.fields);
        // 同一个字段可以出现多次，服务端按出现顺序收，多图不会丢。
        for (final file in currentUpload.allFiles) {
          multipart.files.add(http.MultipartFile.fromBytes(
            currentUpload.field,
            file.bytes,
            filename: file.filename,
          ));
        }
        request = multipart;
      } else {
        final plain = http.Request(currentMethod, currentUri);
        plain.headers.addAll(requestHeaders);
        if (currentForm != null) {
          plain.headers['Content-Type'] = 'application/x-www-form-urlencoded';
          plain.bodyFields = currentForm;
        }
        request = plain;
      }
      request.followRedirects = false;

      final streamed = await _client.send(request).timeout(_timeout);
      final bytes = await streamed.stream.toBytes().timeout(_timeout);
      _absorbCookies(streamed.headers['set-cookie']?.split('\n') ?? const []);

      final status = streamed.statusCode;
      final location = streamed.headers['location'];
      if (status >= 300 && status < 400 && location != null && location.isNotEmpty) {
        currentUri = currentUri.resolve(location);
        if (status == 301 || status == 302 || status == 303) {
          currentMethod = 'GET';
          currentForm = null;
          currentUpload = null;
        }
        continue;
      }

      final body = _decodeBody(bytes, streamed.headers['content-encoding']);
      return HttpResult(status, body, currentUri, streamed.headers);
    }
    throw SiteException('页面跳转过于频繁');
  }

  String _decodeBody(List<int> bytes, String? encoding) {
    try {
      if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        return utf8.decode(gzip.decode(bytes), allowMalformed: true);
      }
      if ((encoding ?? '').toLowerCase().contains('gzip')) {
        return utf8.decode(gzip.decode(bytes), allowMalformed: true);
      }
      if ((encoding ?? '').toLowerCase().contains('deflate')) {
        return utf8.decode(zlib.decode(bytes), allowMalformed: true);
      }
    } catch (_) {
      // 压缩流损坏时退回原文。
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
