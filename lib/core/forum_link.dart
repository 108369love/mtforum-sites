import 'app_config.dart';

/// 站内链接要跳到哪里。
///
/// 同一个主题在 Discuz 里有好几种地址写法，点开正文里的链接时得先认出来，
/// 才谈得上用原生页面打开：
///
/// - 伪静态：`thread-123-1-1.html`、`forum-45-1.html`、`space-uid-7.html`
/// - 查询串：`forum.php?mod=viewthread&tid=123`
/// - 楼层跳转：`forum.php?mod=redirect&goto=findpost&ptid=123&pid=456`
///
/// 最后一种是「跳到某楼」，只带 pid 时不带主题号——站点自己会 302 到
/// 对应主题的那一页。早先的路由只认伪静态，这类地址一路落到内置浏览器，
/// 看起来就像没做原生跳转。
sealed class ForumLink {
  const ForumLink();

  /// 解析一条站内地址；站外或认不出时返回 null，调用方回退到内置浏览器。
  static ForumLink? parse(String raw) {
    final text = raw.trim().replaceAll('&amp;', '&');
    if (text.isEmpty) return null;

    var uri = Uri.tryParse(text);
    if (uri == null) return null;
    if (!uri.hasScheme) uri = AppConfig.uri(text);
    if (!AppConfig.isForumHost(uri.host)) return null;

    final path = uri.path;
    final query = uri.queryParameters;

    // 伪静态优先：它没有 query，认错了也不会误伤别的分支。
    final prettyThread = RegExp(r'thread-(\d+)-\d+-\d+\.html').firstMatch(path);
    if (prettyThread != null) {
      return ThreadLink(tid: int.tryParse(prettyThread.group(1)!) ?? 0);
    }
    final prettyBoard = RegExp(r'forum-(\d+)-1\.html').firstMatch(path);
    if (prettyBoard != null) {
      return BoardLink(fid: int.tryParse(prettyBoard.group(1)!) ?? 0);
    }
    final prettySpace = RegExp(r'space-uid-(\d+)\.html').firstMatch(path);
    if (prettySpace != null) {
      return UserLink(uid: int.tryParse(prettySpace.group(1)!) ?? 0);
    }

    final mod = query['mod'];

    if (mod == 'viewthread') {
      final tid = _int(query['tid']) ?? _int(query['ptid']) ?? 0;
      final pid = _int(query['pid']) ?? 0;
      if (tid > 0 || pid > 0) return ThreadLink(tid: tid, pid: pid);
    }

    // `goto=findpost` 才是楼层跳转；有的站点省掉 goto，只给 pid，
    // 同样按楼层处理，免得掉进浏览器。
    if (mod == 'redirect' && (query['goto'] == 'findpost' || query.containsKey('pid'))) {
      final tid = _int(query['ptid']) ?? _int(query['tid']) ?? 0;
      final pid = _int(query['pid']) ?? 0;
      if (tid > 0 || pid > 0) return ThreadLink(tid: tid, pid: pid);
    }

    if (mod == 'forumdisplay') {
      final fid = _int(query['fid']) ?? 0;
      if (fid > 0) return BoardLink(fid: fid);
    }

    if (mod == 'space') {
      final uid = _int(query['uid']) ?? 0;
      if (uid > 0) return UserLink(uid: uid);
    }

    // 不带 mod 的裸参数写法（`forum.php?tid=123`）在模板里也偶尔出现。
    if (mod == null) {
      final tid = _int(query['tid']) ?? 0;
      if (tid > 0) return ThreadLink(tid: tid, pid: _int(query['pid']) ?? 0);
    }
    return null;
  }

  static int? _int(String? value) {
    final parsed = int.tryParse((value ?? '').trim());
    return parsed != null && parsed > 0 ? parsed : null;
  }
}

/// 主题。tid 为 0 而 pid 有值时，说明这条链接只带了楼号，得先问服务端。
final class ThreadLink extends ForumLink {
  const ThreadLink({required this.tid, this.pid = 0});

  final int tid;
  final int pid;

  bool get needsLookup => tid <= 0 && pid > 0;
}

/// 版块。
final class BoardLink extends ForumLink {
  const BoardLink({required this.fid});

  final int fid;
}

/// 用户空间。
final class UserLink extends ForumLink {
  const UserLink({required this.uid});

  final int uid;
}
