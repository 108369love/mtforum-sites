import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../core/app_config.dart';
import '../data/forum_repository.dart';
import '../data/models.dart';

/// 工具执行过程中可以直接抛给 AI 的错误。
class McpToolException implements Exception {
  const McpToolException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一个 MCP 工具的声明与实现。
class McpTool {
  const McpTool({
    required this.name,
    required this.title,
    required this.description,
    required this.inputSchema,
    required this.run,
    this.write = false,
  });

  final String name;
  final String title;
  final String description;
  final Map<String, dynamic> inputSchema;

  /// 会改动站内数据的操作（发帖、回复、签到）。控制台里可以整体关掉。
  final bool write;

  final Future<Object?> Function(Map<String, dynamic> args) run;

  /// `tools/list` 里返回的形态，字段遵循 MCP 2025-06-18 规范。
  Map<String, dynamic> describe() => <String, dynamic>{
        'name': name,
        'title': title,
        'description': description,
        'inputSchema': inputSchema,
        'annotations': <String, dynamic>{
          'title': title,
          'readOnlyHint': !write,
          'destructiveHint': false,
          'idempotentHint': !write,
          'openWorldHint': true,
        },
      };
}

/// 把论坛仓库的能力映射成 AI 能调用的函数。
///
/// 所有工具都复用 App 内已登录的 [HttpSession]，所以调用方不需要再传账号密码，
/// 权限就是手机上这个账号的权限。
class McpTools {
  McpTools({ForumRepository? repository})
      : _repo = repository ?? ForumRepository.instance;

  final ForumRepository _repo;

  late final List<McpTool> all = <McpTool>[
    McpTool(
      name: 'forum_list_boards',
      title: '列出全部版块',
      description:
          '返回站点的版块分类，以及每个版块的 fid、名称、今日发帖数。'
          '发帖或按版块翻帖前，先用它确认 fid。',
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
      run: (_) => _listBoards(),
    ),
    McpTool(
      name: 'forum_list_threads',
      title: '拉取版块帖子列表',
      description: '按 fid 分页拉取主题列表，返回 tid、标题、作者、回复数、浏览数。',
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'fid': <String, dynamic>{'type': 'integer', 'description': '版块 id'},
          'page': <String, dynamic>{
            'type': 'integer',
            'description': '页码，从 1 开始，默认 1',
            'minimum': 1,
          },
        },
        'required': <String>['fid'],
        'additionalProperties': false,
      },
      run: _listThreads,
    ),
    McpTool(
      name: 'forum_get_thread',
      title: '读取帖子内容',
      description:
          '读取指定主题的正文与楼层，默认返回纯文本（图片以 [图片] 标记）；'
          'format=markdown 时保留代码块、引用和列表结构，适合整理成文档。'
          '要回复某一楼时，从 posts 里取该楼的 pid 传给 forum_reply。',
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'tid': <String, dynamic>{'type': 'integer', 'description': '主题 id'},
          'page': <String, dynamic>{
            'type': 'integer',
            'description': '楼层页码，默认 1',
            'minimum': 1,
          },
          'max_posts': <String, dynamic>{
            'type': 'integer',
            'description': '最多返回几层，默认 10，上限 30',
            'minimum': 1,
            'maximum': 30,
          },
          'format': <String, dynamic>{
            'type': 'string',
            'enum': <String>['text', 'markdown'],
            'description': '正文格式，默认 text',
          },
        },
        'required': <String>['tid'],
        'additionalProperties': false,
      },
      run: _getThread,
    ),
    McpTool(
      name: 'forum_get_post',
      title: '读取单个楼层',
      description:
          '只取一层楼：pid 优先（从 forum_get_thread 的 posts 里拿），也可按 floor 楼层号定位。'
          '返回该楼正文、点评、评分与图片，比整页读取省很多 token。',
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'tid': <String, dynamic>{'type': 'integer', 'description': '主题 id'},
          'pid': <String, dynamic>{'type': 'integer', 'description': '楼层 id，优先使用'},
          'floor': <String, dynamic>{
            'type': 'integer',
            'description': '楼层号（1 起，楼主为 1），没有 pid 时使用',
            'minimum': 1,
          },
          'format': <String, dynamic>{
            'type': 'string',
            'enum': <String>['text', 'markdown'],
            'description': '正文格式，默认 text',
          },
        },
        'required': <String>['tid'],
        'additionalProperties': false,
      },
      run: _getPost,
    ),
    McpTool(
      name: 'forum_search',
      title: '搜索帖子',
      description: '按关键词搜索主题，可选限定版块。返回 tid、标题、作者与摘要。',
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'keyword': <String, dynamic>{'type': 'string', 'description': '搜索关键词'},
          'fid': <String, dynamic>{
            'type': 'integer',
            'description': '限定版块 id，0 表示全站',
          },
          'page': <String, dynamic>{
            'type': 'integer',
            'description': '页码，默认 1',
            'minimum': 1,
          },
        },
        'required': <String>['keyword'],
        'additionalProperties': false,
      },
      run: _search,
    ),
    McpTool(
      name: 'forum_reply',
      title: '回复帖子',
      description:
          '在主题下发表回复。传 reply_to_pid 表示回复某一楼，网页端会显示成带引用的回复；'
          '不传就是普通回帖。正文支持 Discuz 代码（如 [b]粗体[/b]）。',
      write: true,
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'tid': <String, dynamic>{'type': 'integer', 'description': '主题 id'},
          'message': <String, dynamic>{'type': 'string', 'description': '回复正文'},
          'reply_to_pid': <String, dynamic>{
            'type': 'integer',
            'description': '可选，被回复楼层的 pid；不传则为普通回复',
          },
        },
        'required': <String>['tid', 'message'],
        'additionalProperties': false,
      },
      run: _reply,
    ),
    McpTool(
      name: 'forum_create_thread',
      title: '发表新主题',
      description: '在指定版块发一个新帖。subject 为标题，message 为正文（支持 Discuz 代码）。',
      write: true,
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'fid': <String, dynamic>{'type': 'integer', 'description': '版块 id'},
          'subject': <String, dynamic>{'type': 'string', 'description': '帖子标题'},
          'message': <String, dynamic>{'type': 'string', 'description': '帖子正文'},
        },
        'required': <String>['fid', 'subject', 'message'],
        'additionalProperties': false,
      },
      run: _createThread,
    ),
    McpTool(
      name: 'forum_me',
      title: '当前登录账号',
      description: '返回 App 内当前登录的账号信息（uid、用户名、等级、积分等）。',
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
      run: (_) => _me(),
    ),
    McpTool(
      name: 'forum_sign_in',
      title: '每日签到',
      description: '替当前账号执行一次签到。已签到会返回站点提示。',
      write: true,
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
      run: (_) => _signIn(),
    ),
    McpTool(
      name: 'forum_list_notices',
      title: '读取消息提醒',
      description:
          '读取当前账号的提醒：mypost 是「帖子被回复/评论」，interactive 是关注、点赞与 @，'
          'system 是系统通知，app 是应用提醒。不传 view 时读全部，默认只返回前 20 条。',
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'view': <String, dynamic>{
            'type': 'string',
            'enum': <String>['mypost', 'interactive', 'system', 'app'],
            'description': '提醒分类，不传则读全部',
          },
          'unread_only': <String, dynamic>{
            'type': 'boolean',
            'description': '只要未读，默认 false',
          },
          'limit': <String, dynamic>{
            'type': 'integer',
            'description': '最多返回几条，默认 20，上限 50',
            'minimum': 1,
            'maximum': 50,
          },
          'page': <String, dynamic>{
            'type': 'integer',
            'description': '页码，默认 1',
            'minimum': 1,
          },
        },
        'additionalProperties': false,
      },
      run: _listNotices,
    ),
    McpTool(
      name: 'forum_user_profile',
      title: '查看用户资料',
      description: '按 uid 读取某个坛友的主页资料：用户名、等级、积分、发帖数、粉丝数与注册时间。',
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'uid': <String, dynamic>{'type': 'integer', 'description': '用户 id'},
        },
        'required': <String>['uid'],
        'additionalProperties': false,
      },
      run: _userProfile,
    ),
    McpTool(
      name: 'forum_favorite',
      title: '收藏 / 取消收藏',
      description:
          '把主题加入收藏夹，或取消收藏。action=add 收藏、remove 取消、toggle 取反（默认）。'
          '会先读帖子当前的收藏状态，重复操作不会报错。',
      write: true,
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'tid': <String, dynamic>{'type': 'integer', 'description': '主题 id'},
          'action': <String, dynamic>{
            'type': 'string',
            'enum': <String>['add', 'remove', 'toggle'],
            'description': '默认 toggle',
          },
        },
        'required': <String>['tid'],
        'additionalProperties': false,
      },
      run: _favorite,
    ),
    McpTool(
      name: 'forum_edit_post',
      title: '编辑自己的楼层',
      description:
          '改写自己发的帖子或回复。只传 tid+pid 时不会改任何东西，先把原标题和正文原样返回，'
          '方便读过再改；把改好的完整正文放进 message 再调一次才真正提交。'
          '编辑是整篇覆盖，没传的字段保持原样。',
      write: true,
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'tid': <String, dynamic>{'type': 'integer', 'description': '主题 id'},
          'pid': <String, dynamic>{'type': 'integer', 'description': '楼层 id'},
          'subject': <String, dynamic>{
            'type': 'string',
            'description': '可选，新标题；只有主题首楼可改，不传保持原样',
          },
          'message': <String, dynamic>{
            'type': 'string',
            'description': '可选，新的完整正文（Discuz 代码）；不传则只预览原文',
          },
          'fid': <String, dynamic>{
            'type': 'integer',
            'description': '可选，版块 id；不传会自动从帖子里取',
          },
        },
        'required': <String>['tid', 'pid'],
        'additionalProperties': false,
      },
      run: _editPost,
    ),
    McpTool(
      name: 'forum_comment',
      title: '点评楼层',
      description: '对某一楼发一条点评（帖内的小字回复，不是新楼层）。正文支持 Discuz 代码。',
      write: true,
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'tid': <String, dynamic>{'type': 'integer', 'description': '主题 id'},
          'pid': <String, dynamic>{'type': 'integer', 'description': '被点评楼层的 pid'},
          'message': <String, dynamic>{'type': 'string', 'description': '点评内容'},
        },
        'required': <String>['tid', 'pid', 'message'],
        'additionalProperties': false,
      },
      run: _comment,
    ),
    McpTool(
      name: 'forum_send_pm',
      title: '发送私信',
      description: '给指定 uid 的坛友发一条站内私信。',
      write: true,
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'uid': <String, dynamic>{'type': 'integer', 'description': '收件人 uid'},
          'message': <String, dynamic>{'type': 'string', 'description': '私信正文'},
        },
        'required': <String>['uid', 'message'],
        'additionalProperties': false,
      },
      run: _sendPm,
    ),
    McpTool(
      name: 'forum_upload_image',
      title: '上传图片',
      description:
          '把一张图片传到论坛附件库，返回 aid 和可直接粘进正文的 [attachimg]aid[/attachimg]。'
          'data 为 base64（可带 data:image/png;base64, 前缀），解码后不超过 6MB；'
          'filename 建议带扩展名。传了 tid 时按该帖所在版块上传，否则要传 fid。',
      write: true,
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'data': <String, dynamic>{
            'type': 'string',
            'description': '图片的 base64 内容',
          },
          'filename': <String, dynamic>{
            'type': 'string',
            'description': '文件名，如 shot.png；不传按 image.jpg 处理',
          },
          'tid': <String, dynamic>{
            'type': 'integer',
            'description': '可选，目标主题 id（用它的版块做上传上下文）',
          },
          'fid': <String, dynamic>{
            'type': 'integer',
            'description': '可选，版块 id；没有 tid 时必填',
          },
        },
        'required': <String>['data'],
        'additionalProperties': false,
      },
      run: _uploadImage,
    ),
  ];

  McpTool? byName(String name) {
    for (final tool in all) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  // ------------------------------------------------------------ 具体实现

  Future<Object?> _listBoards() async {
    final categories = await _repo.fetchBoards();
    return <String, Object?>{
      'categories': <Object?>[
        for (final category in categories)
          <String, Object?>{
            'name': category.name,
            'boards': <Object?>[
              for (final board in category.boards)
                <String, Object?>{
                  'fid': board.fid,
                  'name': board.name,
                  'today_posts': board.todayPosts,
                },
            ],
          },
      ],
    };
  }

  Future<Object?> _listThreads(Map<String, dynamic> args) async {
    final fid = _int(args['fid']);
    if (fid <= 0) {
      throw const McpToolException('fid 必须是正整数，可先用 forum_list_boards 查询');
    }
    final page = _int(args['page'], fallback: 1).clamp(1, 200);
    final threads = await _repo.fetchBoardThreads(fid, page: page);
    return <String, Object?>{
      'fid': fid,
      'page': page,
      'count': threads.length,
      'threads': <Object?>[for (final t in threads) _summary(t)],
    };
  }

  Future<Object?> _getThread(Map<String, dynamic> args) async {
    final tid = _int(args['tid']);
    if (tid <= 0) throw const McpToolException('tid 必须是正整数');
    final page = _int(args['page'], fallback: 1).clamp(1, 200);
    final maxPosts = _int(args['max_posts'], fallback: 10).clamp(1, 30);
    final format = _format(args);
    final detail = await _repo.fetchThread(tid, page: page);
    return <String, Object?>{
      'tid': detail.tid,
      'title': detail.title,
      'fid': detail.fid,
      'board': detail.boardName,
      'author': detail.author,
      'time': detail.time,
      'views': detail.views,
      'replies': detail.replies,
      'page': page,
      'format': format,
      'has_more': detail.hasMore,
      'url': _threadUrl(detail.tid),
      'posts': <Object?>[
        for (final post in detail.posts.take(maxPosts))
          _postJson(post, markdown: format == 'markdown'),
      ],
    };
  }

  Future<Object?> _getPost(Map<String, dynamic> args) async {
    final tid = _int(args['tid']);
    final pid = _int(args['pid']);
    final floor = _int(args['floor']);
    if (tid <= 0) throw const McpToolException('tid 必须是正整数');
    if (pid <= 0 && floor <= 0) {
      throw const McpToolException(
        'pid 和 floor 至少给一个；pid 可以从 forum_get_thread 返回的 posts 里取',
      );
    }
    final format = _format(args);

    ThreadDetail? detail;
    ForumPost? target;

    if (pid > 0) {
      // 带 pid 请求时服务端会直接跳到该楼所在的页，一次就够。
      detail = await _repo.fetchThread(tid, pid: pid);
      target = _pickPost(detail.posts, pid: pid, floor: 0);
    }

    if (target == null && floor > 0) {
      // 按楼层号先估一页再试；每页层数各站点不同，用首页实际条数推。
      final first = detail ?? await _repo.fetchThread(tid);
      detail = first;
      final perPage = first.posts.isEmpty ? 20 : first.posts.length;
      final guess = ((floor - 1) ~/ perPage) + 1;
      if (guess > 1) {
        final page = await _repo.fetchThread(tid, page: guess.clamp(1, 200));
        target = _pickPost(page.posts, pid: 0, floor: floor);
      }
    }

    // 估算没打中（置顶楼、站点分页规则不一致）就顺序扫几页兜底。
    if (target == null) {
      for (var page = 1; page <= 8; page++) {
        final next = page == 1 && detail != null && detail.posts.isNotEmpty
            ? detail
            : await _repo.fetchThread(tid, page: page);
        detail ??= next;
        target = _pickPost(next.posts, pid: pid, floor: floor);
        if (target != null) break;
        if (!next.hasMore) break;
      }
    }

    if (target == null) {
      throw McpToolException(
        pid > 0 ? '没找到 pid=$pid 的楼层，可能已被删除' : '没找到第 $floor 楼，可能超出前 8 页',
      );
    }

    return <String, Object?>{
      'tid': tid,
      'title': detail?.title ?? '',
      'board': detail?.boardName ?? '',
      'format': format,
      'url': _threadUrl(tid),
      'post': _postJson(target, markdown: format == 'markdown'),
    };
  }

  Future<Object?> _search(Map<String, dynamic> args) async {
    final keyword = _str(args['keyword']);
    if (keyword.isEmpty) throw const McpToolException('keyword 不能为空');
    final fid = _int(args['fid']);
    final page = _int(args['page'], fallback: 1).clamp(1, 50);
    final threads = await _repo.search(keyword, fid: fid, page: page);
    return <String, Object?>{
      'keyword': keyword,
      'fid': fid,
      'page': page,
      'count': threads.length,
      'threads': <Object?>[for (final t in threads) _summary(t)],
    };
  }

  Future<Object?> _reply(Map<String, dynamic> args) async {
    final tid = _int(args['tid']);
    final message = _str(args['message']);
    if (tid <= 0) throw const McpToolException('tid 必须是正整数');
    if (message.isEmpty) throw const McpToolException('message 不能为空');
    final pid = _int(args['reply_to_pid']);

    // 回复接口需要 fid 与 formhash，只能先从帖子里取；
    // 引用条（noticeauthor / noticetrimstr）也必须由服务端生成，
    // 客户端算不出 authcode，所以还要多取一次回复页。
    final detail = await _repo.fetchThread(tid);
    var noticeAuthor = '';
    var noticeTrim = '';
    var noticeAuthorMsg = '';
    if (pid > 0) {
      final ctx = await _repo.fetchReplyContext(
        tid: tid,
        fid: detail.fid,
        pid: pid,
      );
      noticeAuthor = ctx.noticeAuthor;
      noticeTrim = ctx.noticeTrim;
      noticeAuthorMsg = ctx.noticeAuthorMsg;
    }

    final message_ = await _repo.reply(
      tid: tid,
      fid: detail.fid,
      formhash: detail.formhash,
      message: message,
      replyToPid: pid > 0 ? pid : null,
      noticeAuthor: noticeAuthor,
      noticeTrim: noticeTrim,
      noticeAuthorMsg: noticeAuthorMsg,
    );

    return <String, Object?>{
      'ok': true,
      'tid': tid,
      'reply_to_pid': pid > 0 ? pid : null,
      'site_message': message_,
      'url': _threadUrl(tid),
    };
  }

  Future<Object?> _createThread(Map<String, dynamic> args) async {
    final fid = _int(args['fid']);
    final subject = _str(args['subject']);
    final message = _str(args['message']);
    if (fid <= 0) throw const McpToolException('fid 必须是正整数');
    if (subject.isEmpty) throw const McpToolException('subject 不能为空');
    if (message.isEmpty) throw const McpToolException('message 不能为空');

    final result = await _repo.createThread(
      fid: fid,
      subject: subject,
      message: message,
    );
    return <String, Object?>{
      'ok': true,
      'fid': fid,
      'subject': subject,
      'site_message': result,
    };
  }

  Future<Object?> _me() async {
    final profile = await _repo.fetchMyProfile();
    return <String, Object?>{
      'uid': profile.uid,
      'username': profile.username,
      'level': profile.level,
      'group': profile.group,
      'credits': profile.credits,
      'posts': profile.posts,
      'replies': profile.replies,
      'followers': profile.followers,
      'reg_time': profile.regTime,
    };
  }

  Future<Object?> _signIn() async {
    final result = await _repo.signIn();
    return <String, Object?>{'ok': true, 'site_message': result};
  }

  Future<Object?> _listNotices(Map<String, dynamic> args) async {
    const views = <String>{'mypost', 'interactive', 'system', 'app'};
    final view = _str(args['view']);
    if (view.isNotEmpty && !views.contains(view)) {
      throw const McpToolException('view 只能是 mypost / interactive / system / app');
    }
    final limit = _int(args['limit'], fallback: 20).clamp(1, 50);
    final page = _int(args['page'], fallback: 1).clamp(1, 20);
    final unreadOnly = args['unread_only'] == true;
    final items = await _repo.fetchNotices(view: view, page: page);
    final visible = unreadOnly ? items.where((item) => item.unread).toList() : items;
    return <String, Object?>{
      'view': view.isEmpty ? 'all' : view,
      'page': page,
      'count': visible.length,
      'unread': items.where((item) => item.unread).length,
      'notices': <Object?>[
        for (final item in visible.take(limit))
          <String, Object?>{
            'title': item.title,
            'text': item.text,
            'time': item.time,
            'kind': item.kind,
            'unread': item.unread,
            'target': item.target.name,
            if (item.tid > 0) 'tid': item.tid,
            if (item.uid > 0) 'uid': item.uid,
            if (item.url.isNotEmpty) 'url': item.url,
          },
      ],
    };
  }

  Future<Object?> _userProfile(Map<String, dynamic> args) async {
    final uid = _int(args['uid']);
    if (uid <= 0) throw const McpToolException('uid 必须是正整数');
    final (profile, _, followed) = await _repo.fetchUserProfile(uid);
    return <String, Object?>{
      'uid': profile.uid > 0 ? profile.uid : uid,
      'username': profile.username,
      'level': profile.level,
      'group': profile.group,
      'credits': profile.credits,
      'posts': profile.posts,
      'replies': profile.replies,
      'followers': profile.followers,
      'reg_time': profile.regTime,
      'followed_by_me': followed,
    };
  }

  Future<Object?> _favorite(Map<String, dynamic> args) async {
    final tid = _int(args['tid']);
    if (tid <= 0) throw const McpToolException('tid 必须是正整数');
    final action = _str(args['action']).isEmpty ? 'toggle' : _str(args['action']);
    if (!const <String>{'add', 'remove', 'toggle'}.contains(action)) {
      throw const McpToolException('action 只能是 add / remove / toggle');
    }
    final detail = await _repo.fetchThread(tid);
    final before = detail.favorited;
    final want = switch (action) {
      'add' => true,
      'remove' => false,
      _ => !before,
    };
    if (want == before) {
      return <String, Object?>{
        'ok': true,
        'tid': tid,
        'favorited': before,
        'changed': false,
        'site_message': before ? '该主题已在收藏夹里' : '该主题本来就不在收藏夹',
      };
    }
    final message = await _repo.toggleFavorite(
      tid: tid,
      formhash: detail.formhash,
      favorited: before,
      href: detail.favoriteHref,
    );
    return <String, Object?>{
      'ok': true,
      'tid': tid,
      'favorited': want,
      'changed': true,
      'site_message': message,
    };
  }

  Future<Object?> _editPost(Map<String, dynamic> args) async {
    final tid = _int(args['tid']);
    final pid = _int(args['pid']);
    if (tid <= 0 || pid <= 0) {
      throw const McpToolException('tid 与 pid 都必须是正整数');
    }
    var fid = _int(args['fid']);
    if (fid <= 0) {
      final detail = await _repo.fetchThread(tid, pid: pid);
      fid = detail.fid;
    }
    if (fid <= 0) throw const McpToolException('取不到版块 id，请显式传 fid');

    // 编辑是整篇覆盖，必须先把原文拿回来，否则一次改写会把整楼清空。
    final draft = await _repo.fetchEditDraft(tid: tid, pid: pid, fid: fid);
    final subject = _str(args['subject']);
    final message = _str(args['message']);
    final newSubject = subject.isEmpty ? draft.subject : subject;
    final subjectChanged = newSubject != draft.subject;

    if (message.isEmpty && !subjectChanged) {
      return <String, Object?>{
        'ok': true,
        'preview_only': true,
        'tid': tid,
        'pid': pid,
        'subject': draft.subject,
        'message': draft.message,
        'hint': '这是当前原文。把改写后的完整正文放进 message 再调用一次才会提交；'
            '只改标题就传 subject。',
      };
    }

    final result = await _repo.editPost(
      fid: fid,
      tid: tid,
      pid: pid,
      subject: newSubject,
      message: message.isEmpty ? draft.message : message,
      formhash: draft.formhash,
    );
    return <String, Object?>{
      'ok': true,
      'preview_only': false,
      'tid': tid,
      'pid': pid,
      'subject': newSubject,
      'site_message': result,
      'url': _threadUrl(tid),
    };
  }

  Future<Object?> _comment(Map<String, dynamic> args) async {
    final tid = _int(args['tid']);
    final pid = _int(args['pid']);
    final message = _str(args['message']);
    if (tid <= 0 || pid <= 0) {
      throw const McpToolException('tid 与 pid 都必须是正整数');
    }
    if (message.isEmpty) throw const McpToolException('message 不能为空');

    final detail = await _repo.fetchThread(tid, pid: pid);
    if (detail.formhash.isEmpty) {
      throw const McpToolException('没取到 formhash，请确认 App 内已登录');
    }
    final result = await _repo.addComment(
      tid: tid,
      pid: pid,
      message: message,
      formhash: detail.formhash,
    );
    return <String, Object?>{
      'ok': true,
      'tid': tid,
      'pid': pid,
      'site_message': result,
      'url': _threadUrl(tid),
    };
  }

  Future<Object?> _sendPm(Map<String, dynamic> args) async {
    final uid = _int(args['uid']);
    final message = _str(args['message']);
    if (uid <= 0) throw const McpToolException('uid 必须是正整数');
    if (message.isEmpty) throw const McpToolException('message 不能为空');

    // 私信要 formhash，只有用户主页那种带表单的页面才输出。
    final (profile, hash, _) = await _repo.fetchUserProfile(uid);
    if (hash.isEmpty) {
      throw const McpToolException('没取到 formhash，请确认 App 内已登录');
    }
    final result = await _repo.sendPm(uid: uid, formhash: hash, message: message);
    return <String, Object?>{
      'ok': true,
      'uid': uid,
      'to': profile.username.isEmpty ? 'uid=$uid' : profile.username,
      'site_message': result,
    };
  }

  Future<Object?> _uploadImage(Map<String, dynamic> args) async {
    final raw = _str(args['data']);
    if (raw.isEmpty) throw const McpToolException('data 不能为空，需要图片的 base64');

    // 允许客户端直接把 data:image/png;base64,... 整段丢进来。
    var payload = raw;
    final comma = payload.indexOf(',');
    if (payload.startsWith('data:') && comma >= 0) {
      payload = payload.substring(comma + 1);
    }
    final List<int> bytes;
    try {
      bytes = base64Decode(payload.replaceAll(RegExp(r'\s+'), ''));
    } on FormatException {
      throw const McpToolException('data 不是合法的 base64');
    }
    if (bytes.isEmpty) throw const McpToolException('图片内容为空');
    const maxBytes = 6 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      throw McpToolException(
        '图片 ${(bytes.length / 1048576).toStringAsFixed(1)}MB，超过 6MB 上限，'
        '让客户端先压缩再传',
      );
    }

    var fid = _int(args['fid']);
    final tid = _int(args['tid']);
    if (fid <= 0 && tid > 0) fid = (await _repo.fetchThread(tid)).fid;
    if (fid <= 0) throw const McpToolException('需要 fid 或 tid 之一来确定传到哪个版块');

    var filename = _str(args['filename']);
    if (filename.isEmpty) filename = 'image.jpg';

    final info = await _repo.fetchComposeInfo(fid);
    if (info.uploadHash.isEmpty || info.uid <= 0) {
      throw McpToolException(
        '拿不到上传凭证（${info.debug}），先在 App 里打开一次发帖页再试',
      );
    }
    final aid = await _repo.uploadAttachment(
      bytes: bytes,
      filename: filename,
      uploadHash: info.uploadHash,
      uid: info.uid,
      referer: tid > 0
          ? _threadUrl(tid)
          : AppConfig.uri('forum.php', <String, String>{'mod': 'forumdisplay', 'fid': '$fid'})
              .toString(),
      image: true,
      fid: fid,
    );
    return <String, Object?>{
      'ok': true,
      'aid': aid,
      'fid': fid,
      'size': bytes.length,
      'bbcode': '[attachimg]$aid[/attachimg]',
      'hint': '把 bbcode 放进 forum_reply 或 forum_create_thread 的 message 里，图片会显示在原位置。',
    };
  }

  // ------------------------------------------------------------ 小工具

  Map<String, Object?> _postJson(ForumPost post, {bool markdown = false}) => <String, Object?>{
        'pid': post.pid,
        'floor': post.floor,
        'author': post.author,
        'uid': post.uid,
        'time': post.time,
        'is_op': post.isOp,
        'likes': post.likes,
        'text': markdown ? htmlToMarkdown(post.html) : htmlToText(post.html),
        if (post.images.isNotEmpty) 'images': post.images,
        if (post.comments.isNotEmpty)
          'comments': <Object?>[
            for (final comment in post.comments)
              <String, Object?>{
                'author': comment.author,
                'text': comment.text,
                'time': comment.time,
              },
          ],
        if (post.rates.isNotEmpty)
          'rates': <Object?>[
            for (final rate in post.rates)
              <String, Object?>{
                'user': rate.username,
                'uid': rate.uid,
                'score': rate.score,
                'reason': rate.reason,
              },
          ],
      };

  ForumPost? _pickPost(List<ForumPost> posts, {required int pid, required int floor}) {
    for (final post in posts) {
      if (pid > 0 && post.pid == pid) return post;
      if (pid <= 0 && floor > 0 && post.floor == floor) return post;
    }
    return null;
  }

  String _format(Map<String, dynamic> args) =>
      _str(args['format']).toLowerCase() == 'markdown' ? 'markdown' : 'text';

  Map<String, Object?> _summary(ThreadSummary thread) => <String, Object?>{
        'tid': thread.tid,
        'title': thread.title,
        'author': thread.author,
        'board': thread.boardName,
        'time': thread.time,
        'replies': thread.replies,
        'views': thread.views,
        if (thread.excerpt.isNotEmpty) 'excerpt': thread.excerpt,
        'url': _threadUrl(thread.tid),
      };

  String _threadUrl(int tid) =>
      AppConfig.uri('forum.php', <String, String>{'mod': 'viewthread', 'tid': '$tid'})
          .toString();

  int _int(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}'.trim()) ?? fallback;
  }

  String _str(Object? value) => '${value ?? ''}'.trim();

  /// 把 Discuz 正文转成适合给模型读的纯文本。
  ///
  /// 块级元素前后留换行，`<br>` 换算行，图片压成 `[图片]`——模型不需要 alt，
  /// 但需要知道那里有一张图。
  String htmlToText(String html) {
    if (html.trim().isEmpty) return '';
    final fragment = html_parser.parseFragment(html);
    final buffer = StringBuffer();

    void walk(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(node.text.replaceAll(RegExp(r'[ \t\r\n]+'), ' '));
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName ?? '';
      if (tag == 'br') {
        buffer.write('\n');
        return;
      }
      if (tag == 'img') {
        buffer.write('[图片]');
        return;
      }
      if (tag == 'script' || tag == 'style') return;
      if (tag == 'p' || tag == 'div' || tag == 'li' || tag == 'tr') {
        buffer.write('\n');
      }
      for (final child in node.nodes) {
        walk(child);
      }
      if (tag == 'p' ||
          tag == 'div' ||
          tag == 'li' ||
          tag == 'tr' ||
          tag == 'table' ||
          tag == 'blockquote') {
        buffer.write('\n');
      }
    }

    for (final node in fragment.nodes) {
      walk(node);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// 把 Discuz 正文转成 Markdown。
  ///
  /// 和 [htmlToText] 的区别只在于「结构要不要留给下游」：代码块保留围栏和语言、
  /// 引用留成 `>`、列表留成 `-`、链接留成 `[文字](url)`。论坛正文里表格多为
  /// 排版用，转成 `| a | b |` 就够了，不追求对齐成标准表格。
  String htmlToMarkdown(String html) {
    if (html.trim().isEmpty) return '';
    final fragment = html_parser.parseFragment(html);
    final out = StringBuffer();

    String inlineText(dom.Node node) {
      if (node is dom.Text) {
        return node.text.replaceAll(RegExp(r'[ \t\r\n]+'), ' ');
      }
      if (node is! dom.Element) return '';
      final tag = node.localName ?? '';
      String inner() => node.nodes.map(inlineText).join();
      switch (tag) {
        case 'br':
          return '\n';
        case 'script':
        case 'style':
          return '';
        case 'img': {
          final src = node.attributes['src'] ?? '';
          return src.isEmpty ? '[图片]' : '![图片]($src)';
        }
        case 'a': {
          final href = node.attributes['href'] ?? '';
          final label = inner().trim();
          if (label.isEmpty) return '';
          return href.isEmpty || href == label ? label : '[$label]($href)';
        }
        case 'strong':
        case 'b': {
          final text = inner().trim();
          return text.isEmpty ? '' : '**$text**';
        }
        case 'em':
        case 'i': {
          final text = inner().trim();
          return text.isEmpty ? '' : '*$text*';
        }
        case 'code': {
          final text = node.text.trim();
          return text.isEmpty ? '' : '`$text`';
        }
        default:
          return inner();
      }
    }

    void writeQuote(String inner) {
      if (inner.trim().isEmpty) return;
      out.write('\n');
      for (final line in inner.trim().split('\n')) {
        out.write(line.trim().isEmpty ? '>\n' : '> $line\n');
      }
    }

    void block(dom.Node node) {
      if (node is dom.Text) {
        out.write(node.text.replaceAll(RegExp(r'[ \t\r\n]+'), ' '));
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName ?? '';
      switch (tag) {
        case 'script':
        case 'style':
          return;
        case 'br':
          out.write('\n');
          return;
        case 'pre': {
          final lang = _preLanguage(node);
          final code = node.text.trimRight();
          if (code.isEmpty) return;
          out.write('\n```$lang\n$code\n```\n');
          return;
        }
        case 'blockquote':
          writeQuote(htmlToMarkdown(node.innerHtml));
          return;
        case 'h1':
        case 'h2':
        case 'h3':
        case 'h4':
        case 'h5':
        case 'h6': {
          final level = int.tryParse(tag.substring(1)) ?? 3;
          final text = inlineText(node).trim();
          if (text.isNotEmpty) out.write('\n${'#' * level} $text\n');
          return;
        }
        case 'li': {
          final text = inlineText(node).trim();
          if (text.isNotEmpty) out.write('\n- $text');
          return;
        }
        case 'tr': {
          final cells = node.children
              .where((cell) => cell.localName == 'td' || cell.localName == 'th')
              .map((cell) => inlineText(cell).trim())
              .where((cell) => cell.isNotEmpty)
              .toList();
          if (cells.isNotEmpty) out.write('\n| ${cells.join(' | ')} |');
          return;
        }
        case 'table':
          out.write('\n');
          for (final child in node.nodes) {
            block(child);
          }
          out.write('\n');
          return;
        case 'p':
        case 'div':
          out.write('\n');
          if (tag == 'div' && (node.attributes['class'] ?? '').contains('quote')) {
            writeQuote(htmlToMarkdown(node.innerHtml));
          } else {
            for (final child in node.nodes) {
              block(child);
            }
          }
          out.write('\n');
          return;
        default: {
          // 顶层出现 img / a / strong 这类行内元素时，直接按行内规则落地；
          // 只有真的包着块级内容才继续往下走，否则图片链接会被吃掉。
          final hasBlockChild = node.children.any(
            (child) => const <String>{
              'p', 'div', 'ul', 'ol', 'li', 'table', 'tr', 'pre', 'blockquote',
              'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
            }.contains(child.localName),
          );
          if (hasBlockChild) {
            for (final child in node.nodes) {
              block(child);
            }
          } else {
            final text = inlineText(node);
            if (text.trim().isNotEmpty) out.write(text);
          }
        }
      }
    }

    for (final node in fragment.nodes) {
      block(node);
    }
    return out
        .toString()
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// 从 `<pre class="brush: java; ...">` / `language-python` 里挑语言名。
  String _preLanguage(dom.Element node) {
    final code = node.querySelector('code');
    final raw = '${node.attributes['class'] ?? ''} ${code?.attributes['class'] ?? ''}';
    final match = RegExp(r'(?:language-|lang-|brush:\s*)([a-zA-Z0-9+#-]+)').firstMatch(raw);
    return match?.group(1) ?? '';
  }
}
