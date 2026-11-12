/// 正文视频链接识别。
///
/// 站点帖子里的「视频演示」通常就是一条外链（B站、YouTube、直链 mp4 等）。
/// 原先这类链接只能跳系统浏览器，播放体验割裂。这里把常见视频源归一化成
/// 一个可直接交给内置 WebView 播放的目标：能拿到官方 iframe 播放器的就用
/// iframe，拿不到的退回原页面（仍然留在应用内），直链视频则自带一层 <video>。
library;

enum VideoKind {
  bilibili('哔哩哔哩'),
  youtube('YouTube'),
  douyin('抖音'),
  kuaishou('快手'),
  ixigua('西瓜视频'),
  tencent('腾讯视频'),
  youku('优酷'),
  acfun('AcFun'),
  weibo('微博视频'),
  direct('视频文件'),
  other('在线视频');

  const VideoKind(this.label);

  /// 卡片上展示的来源名。
  final String label;
}

class VideoLink {
  const VideoLink({
    required this.url,
    required this.kind,
    required this.playUrl,
    this.videoId,
    this.asPage = false,
  });

  /// 正文里的原始链接（用于「用浏览器打开」）。
  final String url;

  final VideoKind kind;

  /// 交给 WebView 加载的地址：官方 iframe 播放器，或原页面。
  final String playUrl;

  final String? videoId;

  /// true 表示 [playUrl] 是一张网页（原页面），false 表示是 iframe 播放器。
  final bool asPage;

  /// 直链视频文件，播放页需要自己包一层 <video>。
  bool get isDirectFile => kind == VideoKind.direct;

  /// 卡片上的一句话说明。
  String get subtitle {
    switch (kind) {
      case VideoKind.bilibili:
      case VideoKind.youtube:
        return '${kind.label} · 点击在应用内播放';
      case VideoKind.direct:
        return '视频文件 · 点击在应用内播放';
      default:
        return '${kind.label} · 点击在应用内打开';
    }
  }

  @override
  String toString() => 'VideoLink($kind, $playUrl)';
}

/// 把正文里的链接解析成可内嵌播放的视频目标，不是视频链接返回 null。
VideoLink? parseVideoLink(String raw) {
  final url = raw.trim();
  if (url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return null;

  // 直链视频文件：优先判断，避免被后面的站点规则抢走。
  if (_directFile.hasMatch(uri.path)) {
    return VideoLink(url: url, kind: VideoKind.direct, playUrl: url, asPage: true);
  }

  // 哔哩哔哩：BV 号可以直接拼官方播放器，av 号同理；短链只能走原页面。
  if (_isHost(host, 'bilibili.com') || _isHost(host, 'b23.tv')) {
    // 已经是官方播放器地址（帖子里的 [media] 标签常见），原样交给 WebView。
    final queryBv = uri.queryParameters['bvid'];
    final queryAid = uri.queryParameters['aid'];
    if (queryBv != null && queryBv.isNotEmpty) {
      return VideoLink(url: url, kind: VideoKind.bilibili, videoId: queryBv, playUrl: url);
    }
    if (queryAid != null && queryAid.isNotEmpty) {
      return VideoLink(url: url, kind: VideoKind.bilibili, videoId: 'av$queryAid', playUrl: url);
    }
    final bv = _biliBv.firstMatch(url);
    if (bv != null) {
      final id = bv.group(1)!;
      return VideoLink(
        url: url,
        kind: VideoKind.bilibili,
        videoId: id,
        playUrl: 'https://player.bilibili.com/player.html?bvid=$id&autoplay=1&high_quality=1&danmaku=0',
      );
    }
    final av = _biliAv.firstMatch(url);
    if (av != null) {
      final id = av.group(1)!;
      return VideoLink(
        url: url,
        kind: VideoKind.bilibili,
        videoId: 'av$id',
        playUrl: 'https://player.bilibili.com/player.html?aid=$id&autoplay=1&high_quality=1&danmaku=0',
      );
    }
    return VideoLink(url: url, kind: VideoKind.bilibili, playUrl: url, asPage: true);
  }

  // YouTube：watch / youtu.be / shorts / embed 都归一到 embed 地址。
  if (_isHost(host, 'youtube.com') || _isHost(host, 'youtu.be') || _isHost(host, 'youtube-nocookie.com')) {
    final id = _youtubeId(uri);
    if (id != null && id.isNotEmpty) {
      return VideoLink(
        url: url,
        kind: VideoKind.youtube,
        videoId: id,
        playUrl: 'https://www.youtube.com/embed/$id?autoplay=1&playsinline=1',
      );
    }
    return VideoLink(url: url, kind: VideoKind.youtube, playUrl: url, asPage: true);
  }

  if (_isHost(host, 'douyin.com') || _isHost(host, 'iesdouyin.com')) {
    return VideoLink(url: url, kind: VideoKind.douyin, playUrl: url, asPage: true);
  }
  if (_isHost(host, 'kuaishou.com') || _isHost(host, 'gifshow.com')) {
    return VideoLink(url: url, kind: VideoKind.kuaishou, playUrl: url, asPage: true);
  }
  if (_isHost(host, 'ixigua.com')) {
    return VideoLink(url: url, kind: VideoKind.ixigua, playUrl: url, asPage: true);
  }
  if (_isHost(host, 'v.qq.com')) {
    return VideoLink(url: url, kind: VideoKind.tencent, playUrl: url, asPage: true);
  }
  if (_isHost(host, 'youku.com')) {
    return VideoLink(url: url, kind: VideoKind.youku, playUrl: url, asPage: true);
  }
  if (_isHost(host, 'acfun.cn')) {
    return VideoLink(url: url, kind: VideoKind.acfun, playUrl: url, asPage: true);
  }
  if (_isHost(host, 'weibo.com') || _isHost(host, 'video.weibo.com')) {
    return VideoLink(url: url, kind: VideoKind.weibo, playUrl: url, asPage: true);
  }

  return null;
}

/// 正文里整段只贴了一个视频链接时，用它决定是否把链接换成播放卡片。
///
/// 允许前面带「视频演示：」这样的说明，也允许尾部有标点。
VideoLink? parseStandaloneVideo(String text) {
  final trimmed = text.trim().replaceAll(RegExp(r'^[「『“"（(\[]+'), '').trim();
  if (trimmed.isEmpty || trimmed.length > 400) return null;
  final match = _urlInText.firstMatch(trimmed);
  if (match == null) return null;
  // 链接之外只允许少量说明文字，否则说明这是段落而不是单独的演示链接。
  final rest = trimmed.replaceRange(match.start, match.end, '').trim();
  if (rest.replaceAll(_punctuationOnly, '').trim().length > 12) return null;
  return parseVideoLink(match.group(0)!);
}

bool _isHost(String host, String domain) => host == domain || host.endsWith('.$domain');

String? _youtubeId(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host.endsWith('youtu.be')) {
    final seg = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    return seg.isEmpty ? null : seg;
  }
  final segments = uri.pathSegments;
  if (segments.isNotEmpty) {
    final first = segments.first.toLowerCase();
    if ((first == 'shorts' || first == 'embed' || first == 'live') && segments.length > 1) {
      return segments[1];
    }
  }
  final v = uri.queryParameters['v'];
  if (v != null && v.isNotEmpty) return v;
  return null;
}

final RegExp _directFile = RegExp(r'\.(mp4|m4v|webm|ogv|mov|flv|m3u8)$', caseSensitive: false);
final RegExp _biliBv = RegExp(r'/video/(BV[0-9A-Za-z]{8,14})', caseSensitive: false);
final RegExp _biliAv = RegExp(r'/video/av(\d+)', caseSensitive: false);
final RegExp _urlInText = RegExp(r'https?://[^\s<>"“”]+', caseSensitive: false);
final RegExp _punctuationOnly = RegExp(r'[，。；！？、）》】」』,.;:!?:\-—>）)\]】]+');
