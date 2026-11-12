import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/mcp/mcp_server.dart';
import 'package:mt_forum/mcp/mcp_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App 内置 MCP 服务：协议握手、工具清单、权限开关与 HTTP 鉴权。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test 默认把 HttpClient 换成返回 400 的假实现，
  // 这里要连真实的本机服务，所以清掉。
  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    McpServer.instance.resetForTest();
  });

  tearDown(() async {
    await McpServer.instance.stopForTest();
    McpServer.instance.resetForTest();
  });

  test('initialize 回显客户端认识的协议版本', () async {
    final response = await McpServer.instance.dispatchForTest(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': <String, dynamic>{
        'protocolVersion': '2025-03-26',
        'capabilities': <String, dynamic>{},
        'clientInfo': <String, dynamic>{'name': 'test', 'version': '1.0'},
      },
    });

    expect(response, isNotNull);
    final result = response!['result'] as Map<String, dynamic>;
    expect(result['protocolVersion'], '2025-03-26');
    expect((result['capabilities'] as Map)['tools'], isNotNull);
    expect((result['serverInfo'] as Map)['name'], 'mtforum');
  });

  test('客户端版本不认识时回落到最新协议', () async {
    final response = await McpServer.instance.dispatchForTest(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': <String, dynamic>{'protocolVersion': '1999-01-01'},
    });
    final result = response!['result'] as Map<String, dynamic>;
    expect(result['protocolVersion'], '2025-06-18');
  });

  test('通知类消息不返回响应体', () async {
    final response = await McpServer.instance.dispatchForTest(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });
    expect(response, isNull);
  });

  test('tools/list 返回全部工具，schema 自洽', () async {
    final response = await McpServer.instance.dispatchForTest(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/list',
    });

    final tools = (response!['result'] as Map)['tools'] as List;
    expect(tools.length, 16);

    final names = <String>[];
    for (final raw in tools) {
      final tool = raw as Map<String, dynamic>;
      final name = tool['name'] as String;
      names.add(name);
      expect(tool['description'], isNotEmpty);
      expect((tool['annotations'] as Map)['readOnlyHint'], isA<bool>());

      final schema = tool['inputSchema'] as Map<String, dynamic>;
      expect(schema['type'], 'object');
      final properties = schema['properties'] as Map;
      final required = (schema['required'] as List?) ?? const <Object?>[];
      // required 里出现的字段必须在 properties 中声明，否则客户端校验会失败。
      for (final field in required) {
        expect(properties.containsKey(field), isTrue, reason: '$name 缺少 $field 的声明');
      }
    }

    expect(names.toSet().length, names.length, reason: '工具名不能重复');
    expect(
      names,
      containsAll(<String>[
        'forum_list_boards',
        'forum_list_threads',
        'forum_get_thread',
        'forum_search',
        'forum_reply',
        'forum_create_thread',
        'forum_get_post',
        'forum_list_notices',
        'forum_user_profile',
        'forum_favorite',
        'forum_edit_post',
        'forum_comment',
        'forum_send_pm',
        'forum_upload_image',
      ]),
    );
  });

  test('未知方法返回 -32601', () async {
    final response = await McpServer.instance.dispatchForTest(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'foo/bar',
    });
    expect((response!['error'] as Map)['code'], -32601);
  });

  test('未知工具返回 -32602', () async {
    final response = await McpServer.instance.dispatchForTest(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 4,
      'method': 'tools/call',
      'params': <String, dynamic>{'name': 'not_exists', 'arguments': <String, dynamic>{}},
    });
    expect((response!['error'] as Map)['code'], -32602);
  });

  test('关掉写操作后，发帖回复直接被拒', () async {
    await McpServer.instance.setAllowWrite(false);

    final response = await McpServer.instance.dispatchForTest(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 5,
      'method': 'tools/call',
      'params': <String, dynamic>{
        'name': 'forum_reply',
        'arguments': <String, dynamic>{'tid': 1, 'message': 'hi'},
      },
    });

    final result = response!['result'] as Map<String, dynamic>;
    expect(result['isError'], isTrue);
    final content = (result['content'] as List).first as Map<String, dynamic>;
    expect(content['text'], contains('关闭'));
  });

  test('参数不合法时立刻报错，不会去打网络', () async {
    final tools = McpTools();

    await expectLater(
      tools.byName('forum_get_thread')!.run(<String, dynamic>{'tid': 0}),
      throwsA(isA<McpToolException>()),
    );
    await expectLater(
      tools.byName('forum_reply')!.run(<String, dynamic>{'tid': 1, 'message': '   '}),
      throwsA(isA<McpToolException>()),
    );
    await expectLater(
      tools
          .byName('forum_create_thread')!
          .run(<String, dynamic>{'fid': 0, 'subject': 'a', 'message': 'b'}),
      throwsA(isA<McpToolException>()),
    );
    await expectLater(
      tools.byName('forum_list_threads')!.run(<String, dynamic>{'fid': 0}),
      throwsA(isA<McpToolException>()),
    );
    await expectLater(
      tools.byName('forum_search')!.run(<String, dynamic>{'keyword': ' '}),
      throwsA(isA<McpToolException>()),
    );
  });

  test('新增工具在打网络之前就把非法参数挡掉', () async {
    final tools = McpTools();

    Future<void> rejects(String name, Map<String, dynamic> args) async {
      await expectLater(
        tools.byName(name)!.run(args),
        throwsA(isA<McpToolException>()),
        reason: '$name 应该拒绝这组参数：$args',
      );
    }

    await rejects('forum_get_post', <String, dynamic>{'tid': 1});
    await rejects('forum_get_post', <String, dynamic>{'tid': 0, 'pid': 2});
    await rejects('forum_favorite', <String, dynamic>{'tid': 1, 'action': 'pin'});
    await rejects('forum_favorite', <String, dynamic>{'tid': 0});
    await rejects('forum_upload_image', <String, dynamic>{'data': ''});
    await rejects('forum_upload_image', <String, dynamic>{'data': '不是 base64!!'});
    await rejects('forum_send_pm', <String, dynamic>{'uid': 0, 'message': 'hi'});
    await rejects('forum_send_pm', <String, dynamic>{'uid': 7, 'message': '  '});
    await rejects('forum_comment', <String, dynamic>{'tid': 1, 'pid': 0, 'message': 'hi'});
    await rejects('forum_edit_post', <String, dynamic>{'tid': 1, 'pid': 0});
    await rejects('forum_list_notices', <String, dynamic>{'view': 'unknown'});
    await rejects('forum_user_profile', <String, dynamic>{'uid': -3});
  });

  test('正文转 Markdown：代码块、引用、列表与链接都保留结构', () {
    final markdown = McpTools().htmlToMarkdown(
      '<h3>标题</h3>'
      '<div class="quote">引用的一句<br>第二行</div>'
      '<ul><li>甲</li><li>乙</li></ul>'
      '<pre class="brush: java;">class A {}</pre>'
      '<p>看 <a href="https://x.com">这里</a> 和 <strong>重点</strong></p>'
      '<img src="a.png">',
    );

    expect(markdown, contains('### 标题'));
    expect(markdown, contains('> 引用的一句'));
    expect(markdown, contains('> 第二行'));
    expect(markdown, contains('- 甲'));
    expect(markdown, contains('- 乙'));
    expect(markdown, contains('```java'));
    expect(markdown, contains('class A {}'));
    expect(markdown, contains('[这里](https://x.com)'));
    expect(markdown, contains('**重点**'));
    expect(markdown, contains('![图片](a.png)'));
  });

  test('Markdown 里不出现脚本内容，空正文返回空串', () {
    final tools = McpTools();
    expect(
      tools.htmlToMarkdown('<p>正文</p><script>alert(1)</script>'),
      allOf(contains('正文'), isNot(contains('alert'))),
    );
    expect(tools.htmlToMarkdown('   '), isEmpty);
  });

  test('正文转纯文本：保留换行，图片压成标记', () {
    final text = McpTools().htmlToText(
      '<div>第一段<br>第二段</div>'
      '<span class="comiis_postimg"><img src="a.png"></span>'
      '<p>结尾</p>'
      '<script>alert(1)</script>',
    );

    expect(text, contains('第一段'));
    expect(text, contains('第二段'));
    expect(text, contains('[图片]'));
    expect(text, contains('结尾'));
    expect(text, isNot(contains('alert')));
    expect(text.split('\n').length, greaterThan(2));
  });

  test('HTTP 层：无令牌 401，带令牌可以握手', () async {
    final port = await _freePort();
    SharedPreferences.setMockInitialValues(<String, Object>{'mt_forum_mcp_port': port});
    await McpServer.instance.load();
    await McpServer.instance.setAllowLan(false);
    await McpServer.instance.setEnabled(true);

    expect(McpServer.instance.running, isTrue);
    expect(McpServer.instance.token, isNotEmpty);

    final client = HttpClient();
    addTearDown(client.close);

    // 1) 不带令牌
    var request = await client.post('127.0.0.1', port, '/mcp');
    request.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    request.write(jsonEncode(<String, dynamic>{'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'}));
    var response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.unauthorized);

    // 2) 带令牌
    request = await client.post('127.0.0.1', port, '/mcp');
    request.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${McpServer.instance.token}',
    );
    request.write(jsonEncode(<String, dynamic>{'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'}));
    response = await request.close();
    final body = await utf8.decodeStream(response);

    expect(response.statusCode, HttpStatus.ok);
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    expect((decoded['result'] as Map)['tools'], hasLength(16));

    // 3) 通知消息返回 202 且无 body
    request = await client.post('127.0.0.1', port, '/mcp');
    request.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${McpServer.instance.token}',
    );
    request.write(jsonEncode(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    }));
    response = await request.close();
    expect(response.statusCode, HttpStatus.accepted);
    expect(await utf8.decodeStream(response), isEmpty);
  });

  test('令牌可以手动关闭：不带 Authorization 也放行，重新打开又拦住', () async {
    final port = await _freePort();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mt_forum_mcp_port': port,
      'mt_forum_mcp_require_token': false,
    });
    await McpServer.instance.load();
    await McpServer.instance.setAllowLan(false);
    await McpServer.instance.setEnabled(true);

    expect(McpServer.instance.requireToken, isFalse);

    final client = HttpClient();
    addTearDown(client.close);

    Future<HttpClientResponse> call() async {
      final request = await client.post('127.0.0.1', port, '/mcp');
      request.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
      request.write(jsonEncode(<String, dynamic>{'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'}));
      return request.close();
    }

    var response = await call();
    final body = await utf8.decodeStream(response);
    expect(response.statusCode, HttpStatus.ok, reason: '关闭校验后应直接放行');
    expect((jsonDecode(body) as Map)['result'], isNotNull);

    // 重新打开校验，同一个请求（仍不带令牌）要被拒。
    await McpServer.instance.setRequireToken(true);
    response = await call();
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.unauthorized);
  });
}

/// 让系统分配一个空闲端口，关掉后再交给服务用。
Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
