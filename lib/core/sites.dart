import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 站点接入方式。
///
/// MT论坛是 Discuz，移动端模板能解析成原生界面；XDA 这类 XenForo 站点挂在
/// Bunny Shield 后面，首页、版块、RSS 一律先返回一个要跑 JS 才算得出的挑战页，
/// 纯 Dart 的 http 客户端拿不到任何内容（见 docs/SITES.md）。所以站点分成两类：
/// 能解析的走原生，解析不了的整站交给内置浏览器。
enum SiteMode {
  /// Discuz 移动端页面解析：信息流、版块、帖子、消息都是原生界面。
  native,

  /// 站点自带完整前端：装进内置浏览器，登录与发帖都用站点自己的流程。
  web,
}

/// 内置浏览器底部的快捷入口。
class SiteQuickLink {
  const SiteQuickLink(this.label, this.path, this.icon);

  final String label;

  /// 站点内相对路径，空串表示站点首页。
  final String path;
  final IconData icon;
}

/// 一个可切换的站点。
class SiteProfile {
  const SiteProfile({
    required this.id,
    required this.name,
    required this.base,
    required this.mode,
    this.tagline = '',
    this.notes = '',
    this.homePath = '',
    this.quickLinks = const <SiteQuickLink>[],
  });

  /// 稳定标识，存进 SharedPreferences 的就是它，改名不影响已保存的选择。
  final String id;
  final String name;

  /// 站点根地址，统一以 `/` 结尾，拼相对路径时不用再判断。
  final String base;
  final SiteMode mode;

  /// 选择列表里的副标题（一句话说清这个站点怎么接进来的）。
  final String tagline;

  /// 选择页上的补充说明。
  final String notes;

  /// 首页路径；空串表示就是站点根地址。
  final String homePath;
  final List<SiteQuickLink> quickLinks;

  bool get isNative => mode == SiteMode.native;

  /// 站内相对路径拼绝对地址；已经是绝对地址的原样返回。
  Uri uri(String path, [Map<String, String>? query]) {
    final raw = path.isEmpty ? base : path;
    final absolute = raw.startsWith('http://') || raw.startsWith('https://')
        ? raw
        : '$base${raw.replaceFirst(RegExp('^/+'), '')}';
    final parsed = Uri.parse(absolute);
    if (query == null || query.isEmpty) return parsed;
    return parsed.replace(queryParameters: {...parsed.queryParameters, ...query});
  }

  String get homeUrl => uri(homePath).toString();

  static const SiteProfile mtForum = SiteProfile(
    id: 'mt',
    name: 'MT论坛',
    base: 'https://bbs.binmt.cc/',
    mode: SiteMode.native,
    tagline: '原生界面 · bbs.binmt.cc',
    notes: 'Discuz 移动端页面解析。发帖、回复、私信、消息提醒都是原生页面，'
        '和站点共用同一套 Cookie。',
  );

  static const SiteProfile xda = SiteProfile(
    id: 'xda',
    name: 'XDA Forums',
    base: 'https://xdaforums.com/',
    mode: SiteMode.web,
    tagline: '内置浏览器 · xdaforums.com',
    notes: 'XenForo 站点，首页由 Bunny Shield 的 JS 挑战保护，原生抓取拿不到内容，'
        '所以用内置浏览器打开：登录、发帖、附件都走站点自己的流程，'
        '只额外补了顶栏、快捷入口和几处移动端样式修正。',
    quickLinks: <SiteQuickLink>[
      SiteQuickLink('首页', '', Icons.home_outlined),
      SiteQuickLink('版块', 'forums/', Icons.grid_view_outlined),
      SiteQuickLink('搜索', 'search/', Icons.search_rounded),
      SiteQuickLink('我的', 'account/', Icons.person_outline_rounded),
    ],
  );

  /// 内置站点，顺序就是选择列表里的顺序。
  static const List<SiteProfile> builtin = <SiteProfile>[mtForum, xda];

  static const String customId = 'custom';

  static SiteProfile? byId(String id) {
    for (final site in builtin) {
      if (site.id == id) return site;
    }
    return null;
  }

  /// 用户自己填的地址：没写协议就补 https://，路径部分保留。
  ///
  /// 返回 null 表示这串输入没法当站点用（空、不是 http(s)、连主机名都没有）。
  static SiteProfile? tryCustom(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final withScheme = text.startsWith('http://') || text.startsWith('https://') ? text : 'https://$text';
    final parsed = Uri.tryParse(withScheme);
    if (parsed == null || parsed.host.isEmpty) return null;
    if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;
    // 站点根地址：填了具体页面（forum.php、index.php）就退到它所在的目录，
    // 否则拼相对路径会拼出 /forum.php/thread-1.htm 这种不存在的地址。
    var path = parsed.path;
    final slash = path.lastIndexOf('/');
    final lastSegment = slash >= 0 ? path.substring(slash + 1) : path;
    if (lastSegment.contains('.')) {
      path = slash <= 0 ? '/' : path.substring(0, slash);
    }
    if (!path.endsWith('/')) path = '$path/';
    return SiteProfile(
      id: customId,
      name: parsed.host,
      base: '${parsed.scheme}://${parsed.authority}$path',
      mode: SiteMode.web,
      tagline: '自定义站点 · ${parsed.host}',
      notes: '自定义站点一律用内置浏览器打开，不解析页面结构。',
    );
  }
}

/// 当前站点，以及它的持久化。
///
/// 站点是全局选择：切换后整个主框架换一套界面，Discuz 的原生页面只在
/// [SiteMode.native] 站点下存在。
class SiteStore extends ChangeNotifier {
  SiteStore._();

  static final SiteStore instance = SiteStore._();

  static const String _idKey = 'mt_forum_site_id';
  static const String _customKey = 'mt_forum_site_custom';

  SiteProfile _current = SiteProfile.mtForum;

  SiteProfile get current => _current;

  bool get isWeb => _current.mode == SiteMode.web;

  /// 启动时读回上次选的站点。读失败就用默认站点，不值得让启动跟着失败。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_idKey);
      if (id == null || id.isEmpty) return;
      if (id == SiteProfile.customId) {
        final custom = SiteProfile.tryCustom(prefs.getString(_customKey) ?? '');
        if (custom != null) _current = custom;
        return;
      }
      _current = SiteProfile.byId(id) ?? SiteProfile.mtForum;
    } catch (_) {
      // 本地缓存读不出来时继续用 MT论坛，和首次启动一致。
    }
  }

  /// 切到指定站点：先让界面换过去，再落盘。
  ///
  /// 落盘失败只影响下次启动的默认值，不该卡住这次切换，所以写盘放在后面
  /// 并且吞掉异常。
  Future<void> select(SiteProfile site) async {
    _current = site;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_idKey, site.id);
      if (site.id == SiteProfile.customId) {
        await prefs.setString(_customKey, site.base);
      }
    } catch (_) {
      // 内存里已经切过去了，下次启动回到默认站点而已。
    }
  }

  /// 按用户输入的地址切换；地址不合法时返回 false，由调用方给提示。
  Future<bool> selectCustom(String raw) async {
    final site = SiteProfile.tryCustom(raw);
    if (site == null) return false;
    await select(site);
    return true;
  }
}
