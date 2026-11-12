class ForumBoard {
  const ForumBoard({
    required this.fid,
    required this.name,
    this.icon = '',
    this.todayPosts = 0,
  });

  final int fid;
  final String name;
  final String icon;
  final int todayPosts;
}

class ForumCategory {
  const ForumCategory({required this.name, required this.boards});

  final String name;
  final List<ForumBoard> boards;
}

class ThreadSummary {
  const ThreadSummary({
    required this.tid,
    required this.title,
    required this.url,
    this.excerpt = '',
    this.author = '',
    this.avatar = '',
    this.uid = 0,
    this.time = '',
    this.boardName = '',
    this.images = const <String>[],
    this.replies = 0,
    this.views = 0,
  });

  final int tid;
  final String title;
  final String url;
  final String excerpt;
  final String author;
  final String avatar;
  final int uid;
  final String time;
  final String boardName;
  final List<String> images;
  final int replies;
  final int views;
}

class ForumComment {
  const ForumComment({
    required this.author,
    required this.text,
    this.uid = 0,
    this.time = '',
  });

  final String author;
  final String text;
  final int uid;
  final String time;
}

/// 投票选项。
class PollOption {
  const PollOption({required this.id, required this.text, this.votes = 0});

  final int id;
  final String text;
  final int votes;
}

/// 主题投票。
class Poll {
  const Poll({
    this.options = const <PollOption>[],
    this.multiple = false,
    this.total = 0,
    this.voted = false,
    this.expired = false,
  });

  final List<PollOption> options;
  final bool multiple;
  final int total;
  final bool voted;
  final bool expired;
}

/// 提醒点击后要打开的原生页面。
enum NoticeTarget { thread, user, pm, none }

/// 消息通知（回复提醒、@提醒、系统通知）。
///
/// 解析时一次性把「点进去要打开的页面」确定好，界面层只负责按 [target] 跳转，
/// 避免出现「暂时无法识别这条消息的目标页面」这种死路。
class NoticeItem {
  const NoticeItem({
    required this.title,
    this.text = '',
    this.time = '',
    this.url = '',
    this.kind = '',
    this.tid = 0,
    this.uid = 0,
    this.avatar = '',
    this.unread = false,
    this.target = NoticeTarget.none,
  });

  final String title;
  final String text;
  final String time;
  final String url;
  final String kind;

  /// 目标主题编号（兼容 tid / ptid / thread-数字 三种写法）。
  final int tid;

  /// 目标用户编号（回复人、关注人等）。
  final int uid;

  /// 提醒发起人的头像，取不到时为空。
  final String avatar;

  final bool unread;

  final NoticeTarget target;

  bool get hasTarget => target != NoticeTarget.none;
}

/// 好友（空间好友列表）。
class FriendItem {
  const FriendItem({
    required this.uid,
    required this.username,
    this.avatar = '',
    this.note = '',
    this.followers = 0,
    this.following = 0,
    this.isStarred = false,
  });

  final int uid;
  final String username;
  final String avatar;
  final String note;
  final int followers;
  final int following;
  final bool isStarred;

  FriendItem copyWith({String? note, bool? isStarred}) => FriendItem(
        uid: uid,
        username: username,
        avatar: avatar,
        note: note ?? this.note,
        followers: followers,
        following: following,
        isStarred: isStarred ?? this.isStarred,
      );
}

/// 私信会话摘要。
class PmConversation {
  const PmConversation({
    required this.uid,
    required this.name,
    this.avatar = '',
    this.preview = '',
    this.time = '',
    this.unread = false,
  });

  final int uid;
  final String name;
  final String avatar;
  final String preview;
  final String time;
  final bool unread;
}

/// 单条私信。
class PmMessage {
  const PmMessage({
    required this.text,
    this.author = '',
    this.uid = 0,
    this.time = '',
    this.mine = false,
  });

  final String text;
  final String author;
  final int uid;
  final String time;
  final bool mine;
}

/// 一次打赏记录（Discuz 评分日志）。
class RateRecord {
  const RateRecord({
    required this.username,
    this.uid = 0,
    this.score = '',
    this.reason = '',
  });

  final String username;
  final int uid;
  final String score;
  final String reason;
}

/// 站点允许的打赏项（好评 / 金币等，取决于用户组评分类别）。
class RateField {
  const RateField({
    required this.id,
    required this.label,
    this.min = 0,
    this.max = 1,
    this.left = 1,
    this.presets = const <int>[],
  });

  final int id;
  final String label;
  final int min;
  final int max;

  /// 今日剩余可评分额度（站点评分表「今日剩余」）。
  final int left;

  /// 站点下拉实际给出的可选分值（已按今日剩余裁剪）。
  final List<int> presets;

  /// 本次实际可选的最大分值。
  int get ceiling => max < left ? max : left;
}

class RateOptions {
  const RateOptions({
    this.fields = const <RateField>[],
    this.canNotify = false,
    this.notice = '',
  });

  final List<RateField> fields;
  final bool canNotify;

  /// 站点返回的不可打赏提示（如 24 小时内额度已用完）。
  final String notice;

  /// 解析失败时的兜底：站点普通用户组每项每天上限均为 1。
  static const RateOptions fallback = RateOptions(
    fields: <RateField>[
      RateField(id: 1, label: '好评', max: 1),
      RateField(id: 2, label: '金币', max: 1),
    ],
  );
}

class ForumPost {
  ForumPost({
    required this.pid,
    required this.author,
    required this.avatar,
    required this.time,
    required this.html,
    required this.floor,
    this.uid = 0,
    this.level = '',
    this.location = '',
    this.isOp = false,
    this.isPinned = false,
    this.hasSiteFloor = false,
    this.likes = 0,
    this.images = const <String>[],
    this.comments = const <ForumComment>[],
    this.rates = const <RateRecord>[],
    this.rateSummary = '',
  });

  final int pid;
  final String author;
  final String avatar;
  final String time;
  final String html;
  final int floor;
  final int uid;
  final String level;
  final String location;
  final bool isOp;
  final bool isPinned;

  /// 楼层号是否来自站点（置顶回复的「来自2#」），来自站点时不能再按顺序重编。
  final bool hasSiteFloor;
  final int likes;
  final List<String> images;
  final List<ForumComment> comments;
  final List<RateRecord> rates;
  final String rateSummary;

  /// 楼层标签：主题正文不参与评论排序；首条评论为沙发，第十楼为下水道。
  String get floorLabel => isPinned ? '置顶 $floor#' : seatLabel;

  String get seatLabel {
    if (floor <= 1) return '';
    const seats = <String>[
      '沙发', '椅子', '板凳', '地毯', '凉席', '报纸', '地板', '地下室', '下水道',
    ];
    // floor=2 为首条评论（沙发），floor=10 为第九条评论（下水道）。
    final index = floor - 2;
    return index >= 0 && index < seats.length ? seats[index] : '$floor楼';
  }

  ForumPost copyWith({
    int? floor,
    int? uid,
    String? avatar,
    bool? isOp,
    bool? isPinned,
    bool? hasSiteFloor,
  }) =>
      ForumPost(
        pid: pid,
        author: author,
        avatar: avatar ?? this.avatar,
        time: time,
        html: html,
        floor: floor ?? this.floor,
        uid: uid ?? this.uid,
        level: level,
        location: location,
        isOp: isOp ?? this.isOp,
        isPinned: isPinned ?? this.isPinned,
        hasSiteFloor: hasSiteFloor ?? this.hasSiteFloor,
        likes: likes,
        images: images,
        comments: comments,
        rates: rates,
        rateSummary: rateSummary,
      );
}

class ThreadDetail {
  const ThreadDetail({
    required this.tid,
    required this.title,
    required this.fid,
    required this.boardName,
    required this.author,
    required this.time,
    required this.views,
    required this.replies,
    required this.posts,
    required this.formhash,
    required this.hasMore,
    this.page = 1,
    required this.isLoggedIn,
    this.likes = 0,
    this.dislikes = 0,
    this.liked = false,
    this.likeHref = '',
    this.uploadHash = '',
    this.uid = 0,
    this.poll,
    this.notice = '',
    this.favorited = false,
    this.favoriteHref = '',
    this.kickToken = '',
    this.kickVotes = 0,
    this.kickLimit = 5,
  });

  final int tid;
  final String title;
  final int fid;
  final String boardName;
  final String author;
  final String time;
  final int views;
  final int replies;
  final List<ForumPost> posts;
  final String formhash;
  final bool hasMore;

  /// 这一份数据其实是第几页。
  ///
  /// 平时就等于请求的页码；按 pid 定位楼层时服务端会 302 到该楼所在页，
  /// 请求写的 `page=1` 已经不作数，翻页得从这个真实页码继续。
  final int page;

  final bool isLoggedIn;
  final int likes;
  final int dislikes;

  /// 当前账号是否已经赞过该主题。Discuz 没有查询接口，只能从页面按钮状态判断；
  /// 判断不出来时按未赞处理，点赞成功后再本地置位。
  final bool liked;

  /// 页面上「赞」按钮的链接。已赞时它通常就是取消地址，取消时直接用，
  /// 比自己拼 `do=cancel` 可靠。
  final String likeHref;

  /// 当前页面用于附件上传的 hash 与 uid（游客为 0）。
  final String uploadHash;
  final int uid;
  final Poll? poll;
  final String notice;

  /// 是否已收藏该主题，以及页面上收藏/取消收藏的原始链接。
  final bool favorited;
  final String favoriteHref;

  /// 踢帖入口（站点插件 bin_post_report 注入的 token 与当前票数）。
  final String kickToken;
  final int kickVotes;
  final int kickLimit;

  ThreadDetail copyWith({
    List<ForumPost>? posts,
    bool? hasMore,
    int? likes,
    int? dislikes,
    int? replies,
    bool? liked,
  }) =>
      ThreadDetail(
        tid: tid,
        title: title,
        fid: fid,
        boardName: boardName,
        author: author,
        time: time,
        views: views,
        replies: replies ?? this.replies,
        posts: posts ?? this.posts,
        formhash: formhash,
        hasMore: hasMore ?? this.hasMore,
        isLoggedIn: isLoggedIn,
        likes: likes ?? this.likes,
        dislikes: dislikes ?? this.dislikes,
        liked: liked ?? this.liked,
        likeHref: likeHref,
        uploadHash: uploadHash,
        uid: uid,
        poll: poll,
        notice: notice,
        favorited: favorited,
        favoriteHref: favoriteHref,
        kickToken: kickToken,
        kickVotes: kickVotes,
        kickLimit: kickLimit,
      );
}

class ComposeInfo {
  const ComposeInfo({
    required this.formhash,
    required this.uploadHash,
    required this.uid,
    this.debug = '',
  });

  final String formhash;
  final String uploadHash;
  final int uid;

  /// 凭证没取到时用来定位问题的一行摘要（页面大小、有没有 hash、uid 多少），
  /// 直接拼进错误提示里，用户截图就能看出是哪一步断了。
  final String debug;
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.username,
    this.avatar = '',
    this.level = '',
    this.credits = '',
    this.posts = '',
    this.replies = '',
    this.followers = '',
    this.regTime = '',
    this.group = '',
  });

  final int uid;
  final String username;
  final String avatar;
  final String level;
  final String credits;
  final String posts;
  final String replies;
  final String followers;
  final String regTime;
  final String group;
}

/// 小黑屋记录（forum.php?mod=misc&action=showdarkroom）。
class DarkRoomEntry {
  const DarkRoomEntry({
    required this.uid,
    required this.name,
    required this.action,
    this.expiry = '',
    this.time = '',
  });

  final int uid;
  final String name;
  final String action;
  final String expiry;
  final String time;
}

/// 勋章目录条目。
class MedalItem {
  const MedalItem({required this.name, this.image = '', this.desc = ''});

  final String name;
  final String image;
  final String desc;
}

/// 勋章获得记录。
class MedalRecord {
  const MedalRecord({
    required this.uid,
    required this.name,
    required this.medal,
    this.avatar = '',
    this.time = '',
  });

  final int uid;
  final String name;
  final String medal;
  final String avatar;
  final String time;
}

/// 积分项（金币、威望、贡献等）。
class CreditItem {
  const CreditItem({required this.name, required this.value, this.highlight = false});

  final String name;
  final String value;
  final bool highlight;
}

/// 积分页的余额摘要。
class CreditSummary {
  const CreditSummary({
    this.items = const <CreditItem>[],
    this.total = '',
    this.formula = '',
  });

  final List<CreditItem> items;
  final String total;
  final String formula;
}

/// 积分交易记录。
class CreditLog {
  const CreditLog({
    required this.operation,
    required this.change,
    required this.detail,
    required this.time,
  });

  final String operation;
  final String change;
  final String detail;
  final String time;
}

/// 道具商店条目。
class MagicItem {
  const MagicItem({
    required this.mid,
    required this.name,
    this.image = '',
    this.description = '',
    this.priceText = '',
    this.price = '',
    this.soldOut = false,
    this.canGive = false,
    this.saleVolume = '',
  });

  /// 道具 identifier，购买/赠送时作为 `mid` 提交。
  final String mid;
  final String name;
  final String image;
  final String description;
  final String priceText;
  final String price;
  final bool soldOut;

  /// 站点是否开放「购买后赠送」。
  final bool canGive;

  /// 热销榜上的已售数量文案。
  final String saleVolume;
}

/// 我的道具。
class MyMagic {
  const MyMagic({
    required this.id,
    required this.name,
    this.image = '',
    this.description = '',
    this.num = 0,
    this.weight = '',
    this.canUse = false,
    this.canGive = false,
    this.canSell = false,
    this.canDrop = false,
  });

  /// 数字道具 id，使用/赠送/出售/丢弃时作为 `magicid` 提交。
  final int id;
  final String name;
  final String image;
  final String description;
  final int num;
  final String weight;
  final bool canUse;
  final bool canGive;
  final bool canSell;
  final bool canDrop;
}

/// 我的道具页内容。
class MagicBox {
  const MagicBox({this.capacity = '', this.items = const <MyMagic>[]});

  final String capacity;
  final List<MyMagic> items;
}

/// 道具日志条目。
class MagicLogEntry {
  const MagicLogEntry({required this.title, this.time = '', this.detail = ''});

  final String title;
  final String time;
  final String detail;
}

enum MagicFieldType { text, radio, select, textarea }

class MagicFieldOption {
  const MagicFieldOption(this.value, this.label);

  final String value;
  final String label;
}

/// 使用道具时站点要求的表单字段（如主题 ID、颜色等）。
class MagicFormField {
  const MagicFormField({
    required this.name,
    this.label = '',
    this.type = MagicFieldType.text,
    this.value = '',
    this.options = const <MagicFieldOption>[],
  });

  final String name;
  final String label;
  final MagicFieldType type;
  final String value;
  final List<MagicFieldOption> options;
}

/// 使用道具的操作页表单。
class MagicUseForm {
  const MagicUseForm({
    required this.formhash,
    this.hidden = const <String, String>{},
    this.fields = const <MagicFormField>[],
  });

  final String formhash;
  final Map<String, String> hidden;
  final List<MagicFormField> fields;
}

/// 积分商城下单：确认页解析出的表单。
class MallCheckout {
  const MallCheckout({
    this.action = '',
    this.formhash = '',
    this.hidden = const <String, String>{},
    this.fields = const <MagicFormField>[],
    this.preview = '',
  });

  /// 表单提交地址；为空表示该页已是结果页。
  final String action;
  final String formhash;
  final Map<String, String> hidden;
  final List<MagicFormField> fields;

  /// 确认页 / 结果页上的可见文本（商品信息、卡密等）。
  final String preview;

  bool get isForm => action.isNotEmpty;
}

/// 站点功能模块中的一行（道具、任务、积分、推广等）。
class SiteRow {
  const SiteRow({
    required this.title,
    this.subtitle = '',
    this.image = '',
    this.href = '',
  });

  final String title;
  final String subtitle;
  final String image;
  final String href;
}

/// 积分商城商品详情（keke_integralmall 插件）。
class MallProduct {
  const MallProduct({
    required this.tid,
    required this.title,
    this.image = '',
    this.price = '',
    this.marketPrice = '',
    this.stock = '',
    this.sold = '',
    this.startAt,
    this.endAt,
    this.views = '',
    this.warning = '',
    this.buyHref = '',
    this.statusHref = '',
    this.records = const [],
  });

  final int tid;
  final String title;
  final String image;
  final String price;
  final String marketPrice;
  final String stock;
  final String sold;

  /// 抢购开始 / 结束时间，剩余时间由客户端实时计算。
  final DateTime? startAt;
  final DateTime? endAt;
  final String views;
  final String warning;
  final String buyHref;
  final String statusHref;
  final List<SiteRow> records;
}

/// 资料设置·基本资料（`home.php?mod=spacecp&ac=profile&op=base`）。
///
/// 站点把每个字段的可见范围打包成 `privacy[字段]`，取值 0 公开 / 1 好友可见 /
/// 3 保密；居住地则是省、市、区、街道四个隐藏字段拼出来的文本，页面上只显示
/// 拼好的那一串，所以这里保留 [resideText] 原文，提交时再拆回去。
class ProfileBaseSettings {
  const ProfileBaseSettings({
    required this.formhash,
    this.occupation = '',
    this.realname = '',
    this.gender = 0,
    this.birthYear = '',
    this.birthMonth = '',
    this.birthDay = '',
    this.resideText = '',
    this.privacy = const <String, String>{},
  });

  final String formhash;
  final String occupation;
  final String realname;

  /// 0 保密 / 1 男 / 2 女。
  final int gender;
  final String birthYear;
  final String birthMonth;
  final String birthDay;
  final String resideText;
  final Map<String, String> privacy;

  bool get hasBirthday => birthYear.isNotEmpty && birthMonth.isNotEmpty && birthDay.isNotEmpty;

  String get birthdayText => hasBirthday
      ? '$birthYear-${birthMonth.padLeft(2, '0')}-${birthDay.padLeft(2, '0')}'
      : '';

  String privacyOf(String field) => privacy[field] ?? '0';

  ProfileBaseSettings copyWith({
    String? occupation,
    String? realname,
    int? gender,
    String? birthYear,
    String? birthMonth,
    String? birthDay,
    String? resideText,
    Map<String, String>? privacy,
  }) =>
      ProfileBaseSettings(
        formhash: formhash,
        occupation: occupation ?? this.occupation,
        realname: realname ?? this.realname,
        gender: gender ?? this.gender,
        birthYear: birthYear ?? this.birthYear,
        birthMonth: birthMonth ?? this.birthMonth,
        birthDay: birthDay ?? this.birthDay,
        resideText: resideText ?? this.resideText,
        privacy: privacy ?? this.privacy,
      );
}

/// 资料设置·联系方式（`ac=profile&op=contact`）。邮箱只能去密码页改，这里只读。
class ProfileContactSettings {
  const ProfileContactSettings({
    required this.formhash,
    this.qq = '',
    this.mobile = '',
    this.email = '',
    this.privacy = const <String, String>{},
  });

  final String formhash;
  final String qq;
  final String mobile;
  final String email;
  final Map<String, String> privacy;

  String privacyOf(String field) => privacy[field] ?? '0';

  ProfileContactSettings copyWith({
    String? qq,
    String? mobile,
    Map<String, String>? privacy,
  }) =>
      ProfileContactSettings(
        formhash: formhash,
        qq: qq ?? this.qq,
        mobile: mobile ?? this.mobile,
        email: email,
        privacy: privacy ?? this.privacy,
      );
}

/// 资料设置·个人信息（`ac=profile&op=info`）：自我介绍、自定义头衔、个人签名。
class ProfileInfoSettings {
  const ProfileInfoSettings({
    required this.formhash,
    this.bio = '',
    this.customStatus = '',
    this.signature = '',
    this.privacy = const <String, String>{},
  });

  final String formhash;
  final String bio;
  final String customStatus;

  /// Discuz 代码（`[b]`、`[img]` 等），与网页端同一套语法。
  final String signature;
  final Map<String, String> privacy;

  String privacyOf(String field) => privacy[field] ?? '0';

  ProfileInfoSettings copyWith({
    String? bio,
    String? customStatus,
    String? signature,
    Map<String, String>? privacy,
  }) =>
      ProfileInfoSettings(
        formhash: formhash,
        bio: bio ?? this.bio,
        customStatus: customStatus ?? this.customStatus,
        signature: signature ?? this.signature,
        privacy: privacy ?? this.privacy,
      );
}

/// 隐私筛选（`ac=privacy&op=base`）：主页、广播、空间动态的可见范围。
class PrivacySettings {
  const PrivacySettings({
    required this.formhash,
    this.friend = '0',
    this.wall = '0',
    this.home = '0',
  });

  final String formhash;
  final String friend;
  final String wall;
  final String home;

  PrivacySettings copyWith({String? friend, String? wall, String? home}) => PrivacySettings(
        formhash: formhash,
        friend: friend ?? this.friend,
        wall: wall ?? this.wall,
        home: home ?? this.home,
      );
}

/// 改名申请（`plugin.php?id=nimba_rename`）。
///
/// 站点不走 spacecp，而是装了一个改名插件：填新用户名 + 理由提交，扣一次
/// 金币，再由管理员人工改名。表单里除了这两个字段就只有 formhash。
class RenameInfo {
  const RenameInfo({required this.formhash, required this.fee});

  final String formhash;

  /// 本次申请要扣的金币，由插件页文案解析，页面改价也能跟上。
  final int fee;

  bool get canSubmit => formhash.isNotEmpty;
}

/// 我的等级（`home.php?mod=spacecp&ac=usergroup&mobile=2`）。
///
/// 移动模板把用户组信息和权限表放在同一页：头部是当前等级、进度和还差多少
/// 积分升级；下面一张两列表，左边权限名、右边值或一个「有/无」图标。
class UserGroupInfo {
  const UserGroupInfo({
    required this.name,
    required this.level,
    required this.nextLevel,
    required this.nextName,
    required this.credits,
    required this.remaining,
    required this.progress,
    required this.avatar,
    required this.permissions,
  });

  /// 用户组名，如「硕士生」。
  final String name;

  /// 当前等级，如 `Lv.6`。
  final String level;
  final String nextLevel;
  final String nextName;
  final String credits;

  /// 距离下一级还差多少积分；已经是最高级时为 0。
  final int remaining;

  /// 0–1 的升级进度，用于画进度条。
  final double progress;
  final String avatar;
  final List<GroupPermission> permissions;

  bool get hasNext => nextName.isNotEmpty;
}

/// 用户组权限的一行。`allowed` 为 null 表示这一行是具体数值/文字。
class GroupPermission {
  const GroupPermission({required this.name, this.value = '', this.allowed});

  final String name;
  final String value;
  final bool? allowed;
}
