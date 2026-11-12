import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';
import 'package:mt_forum/data/models.dart';

/// 提醒 / 粉丝列表的解析回归测试。
///
/// 两个线上问题的根因都在解析层：
/// 1. Discuz 的跳转链接用 `ptid=`，旧正则只认 `tid=`，导致提醒没有落地页；
/// 2. 关注类列表里「6 关注」这种计数链接也带 uid，被误当成昵称。
void main() {
  final repo = ForumRepository.instance;

  const desktopNotice = '''
<div class="nts">
  <dl class="cl">
    <dt class="avt"><a href="home.php?mod=space&amp;uid=1001"><img src="uc_server/avatar.php?uid=1001"></a></dt>
    <dd class="ntc_body">
      <a href="home.php?mod=space&amp;uid=1001">张三</a> 回复了您的帖子
      <a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=8888&amp;pid=77777">关于 MT 管理器的问题</a>
      <a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=8888&amp;pid=77777">查看</a>
    </dd>
    <dd class="ntc_time xg1">2026-10-29 09:00</dd>
  </dl>
  <dl class="cl">
    <dd class="ntc_body">
      <a href="home.php?mod=space&amp;uid=2002">李四</a> 关注了您
      <a href="home.php?mod=space&amp;uid=2002">查看</a>
    </dd>
    <dd class="ntc_time xg1">2026-10-29 08:30</dd>
  </dl>
  <dl class="cl">
    <dd class="ntc_body">您的账号已通过审核</dd>
    <dd class="ntc_time xg1">2026-10-29 08:00</dd>
  </dl>
</div>
''';

  const mobileNotice = '''
<div class="comiis_notice_list">
  <li class="comiis_notice_item new">
    <div class="comiis_notice_content">
      <a href="space-uid-3003.html">王五</a> 在主题
      <a href="thread-4321-1-1.html">MT论坛软件端</a> 中提到了您
      <a href="home.php?mod=space&amp;do=notice&amp;view=friend">查看</a>
    </div>
  </li>
  <li class="comiis_notice_item">
    <div class="comiis_notice_content">
      <a href="home.php?mod=space&amp;do=notice&amp;view=friend">查看</a>
    </div>
  </li>
</div>
''';

  test('回复提醒用 ptid 识别主题，并把「查看」从标题里去掉', () {
    final items = repo.parseNoticeHtml(desktopNotice, view: 'interactive');
    expect(items.length, 3);

    final reply = items.first;
    expect(reply.target, NoticeTarget.thread);
    expect(reply.tid, 8888);
    expect(reply.title.contains('查看'), isFalse);
    expect(reply.title.contains('回复了您的帖子'), isTrue);
    expect(reply.time, '2026-10-29 09:00');

    final follow = items[1];
    expect(follow.target, NoticeTarget.user);
    expect(follow.uid, 2002);
    expect(follow.title.contains('关注了您'), isTrue);
  });

  test('没有落地页的提醒保留正文，纯「查看」空壳行被丢弃', () {
    final interactive = repo.parseNoticeHtml(desktopNotice, view: 'interactive');
    expect(interactive.length, 3);
    expect(interactive.last.target, NoticeTarget.none);
    expect(interactive.last.title, '您的账号已通过审核');

    final system = repo.parseNoticeHtml(desktopNotice, view: 'system');
    expect(system.length, 3);
    expect(system.last.target, NoticeTarget.none);

    // 只有「查看」一行、没有任何目标的卡片不应变成一条提醒。
    final mobile = repo.parseNoticeHtml(mobileNotice, view: 'friend');
    expect(mobile.length, 1);
  });

  test('移动模板的一条提醒只产生一条记录，不重复也不留死链', () {
    final items = repo.parseNoticeHtml(mobileNotice, view: 'friend');
    expect(items.length, 1);
    expect(items.single.target, NoticeTarget.thread);
    expect(items.single.tid, 4321);
    expect(items.single.title.contains('MT论坛软件端'), isTrue);
    expect(items.single.title.contains('查看'), isFalse);
  });

  test('粉丝列表取昵称而不是「6 关注」计数链接', () {

    const html = '''
<ul id="follow_ul">
  <li>
    <div class="avt"><a href="home.php?mod=space&amp;uid=101"><img src="uc_server/avatar.php?uid=101"></a></div>
    <div class="con">
      <h2><a href="home.php?mod=space&amp;uid=101">凹凹凹凸曼</a></h2>
      <p>
        <a href="home.php?mod=follow&amp;do=following&amp;uid=101">6 关注</a>
        <a href="home.php?mod=follow&amp;do=follower&amp;uid=101">4 粉丝</a>
      </p>
      <a href="home.php?mod=spacecp&amp;ac=follow&amp;op=add&amp;fuid=101&amp;hash=abc">关注</a>
    </div>
  </li>
  <li>
    <a href="home.php?mod=follow&amp;do=following&amp;uid=202">1650 关注</a>
    <a href="home.php?mod=space&amp;uid=202"><img src="uc_server/avatar.php?uid=202"></a>
    <a href="home.php?mod=space&amp;uid=202">zhongang</a>
    <a href="home.php?mod=follow&amp;do=follower&amp;uid=202">283 粉丝</a>
  </li>
</ul>
''';
    final items = repo.parseFollowHtml(html);
    expect(items.length, 2);

    expect(items[0].username, '凹凹凹凸曼');
    expect(items[0].uid, 101);
    expect(items[0].following, 6);
    expect(items[0].followers, 4);

    expect(items[1].username, 'zhongang');
    expect(items[1].following, 1650);
    expect(items[1].followers, 283);
  });

  // 下面两段 HTML 取自 Discuz X3.5 触屏版模板
  // （template/default/touch/home/space_notice.php、follow_feed.php），
  // 用来锁定「网页端真实结构」下的解析结果。
  test('触屏版提醒卡片 .notice-list-item 能解析出时间与帖子目标', () {
    const html = '''
<div id="notice_ul" class="notice-list">
  <div class="notice-list-item" notice="11">
    <div class="notice-list-avatar">
      <a href="home.php?mod=space&amp;uid=1001"><img src="uc_server/avatar.php?uid=1001"></a>
    </div>
    <div class="notice-list-info">
      <div class="notice-list-meta">
        <span class="notice-list-time">2 小时前</span>
        <a href="home.php?mod=spacecp&amp;ac=common&amp;op=ignore&amp;authorid=1001" class="dialog notice-list-shield">屏蔽</a>
      </div>
      <div class="notice-list-body">
        <a href="home.php?mod=space&amp;uid=1001">张三</a> 回复了您的帖子
        <a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=8888&amp;pid=77777">关于 MT 管理器的问题</a>
        <a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=8888&amp;pid=77777">查看</a>
      </div>
    </div>
  </div>
</div>
''';
    final items = repo.parseNoticeHtml(html, view: 'interactive');
    expect(items.length, 1);
    expect(items.single.target, NoticeTarget.thread);
    expect(items.single.tid, 8888);
    expect(items.single.time, '2 小时前');
    expect(items.single.title.contains('屏蔽'), isFalse);
    expect(items.single.title.endsWith('查看'), isFalse);
  });

  test('触屏版粉丝行 dl.b_b 取昵称与「粉丝: 4 人 / 关注: 6 人」', () {
    const html = '''
<div class="xld xlda">
  <dl class="b_b cl">
    <dd class="m avt"><a href="home.php?mod=space&amp;uid=101" target="_blank"><img src="uc_server/avatar.php?uid=101"></a></dd>
    <dt class="y"><p class="xw0"><a id="a_followmod_101" href="home.php?mod=spacecp&amp;ac=follow&amp;op=del&amp;fuid=101" class="flw_btn_unfo dialog">取消关注</a></p></dt>
    <dt><a href="home.php?mod=space&amp;uid=101" class="xs2">凹凹凹凸曼</a>&nbsp;<span class="xg1 xs1 xw0"></span></dt>
    <dd><p>
      粉丝: <a href="home.php?mod=follow&amp;do=follower&amp;uid=101"><strong class="xi2" id="followernum_101">4</strong></a>人 &nbsp;
      关注: <a href="home.php?mod=follow&amp;do=following&amp;uid=101"><strong class="xi2">6</strong></a>人
    </p></dd>
  </dl>
</div>
''';
    final items = repo.parseFollowHtml(html);
    expect(items.length, 1);
    expect(items.single.username, '凹凹凹凸曼');
    expect(items.single.uid, 101);
    expect(items.single.followers, 4);
    expect(items.single.following, 6);
  });

  test('提醒页顶部的「消息」导航不会被当成一条私信提醒', () {
    // Discuz 触屏提醒页顶部有一条 .dhnv 导航：消息（do=pm）+ 我的提醒。
    const html = '''
<div class="dhnv flex-box cl">
  <a href="home.php?mod=space&amp;do=pm" class="flex">消息</a>
  <a href="home.php?mod=space&amp;do=notice" class="flex mon">我的提醒</a>
</div>
<div class="empty-box"><h4>暂无新提醒</h4></div>
''';
    expect(repo.parseNoticeHtml(html, view: 'mypost'), isEmpty);

    // 部分主题把导航渲染成列表项，同样不能变成提醒。
    const listNav = '''
<ul class="notice">
  <li><a href="home.php?mod=space&amp;do=pm">消息</a></li>
</ul>
''';
    expect(repo.parseNoticeHtml(listNav, view: 'interactive'), isEmpty);
  });

  test('指向具体会话的私信提醒仍然保留', () {
    const html = '''
<dl class="cl">
  <dd class="ntc_body">
    <a href="home.php?mod=space&amp;do=pm&amp;touid=2002">李四</a> 给您发送了短消息
    <a href="home.php?mod=space&amp;do=pm&amp;touid=2002">查看</a>
  </dd>
  <dd class="ntc_time xg1">2026-10-29 08:30</dd>
</dl>
''';
    final items = repo.parseNoticeHtml(html, view: 'interactive');
    expect(items.length, 1);
    expect(items.single.target, NoticeTarget.pm);
    expect(items.single.uid, 2002);
  });

  test('私信列表用 space-uid 链接时也能取到昵称', () {
    const html = '''
<dl id="pmlist_0" class="cl">
  <dd class="avt"><a href="space-uid-119603.html"><img src="uc_server/avatar.php?uid=119603"></a></dd>
  <dd class="ptm">
    <a href="space-uid-119603.html" class="xg1">大佬</a>
    <span class="xg1">2026-7-25 18:33</span><br>
    <a href="home.php?mod=space&amp;do=pm&amp;subop=view&amp;touid=119603">大佬ai弄好了么</a>
  </dd>
</dl>
<dl id="pmlist_1" class="cl">
  <dd class="avt"><a href="home.php?mod=space&amp;uid=109717"><img src="uc_server/avatar.php?uid=109717"></a></dd>
  <dd class="ptm">
    <a href="home.php?mod=space&amp;uid=109717" class="xg1">老王</a>
    <span class="xg1">2025-5-24 22:33</span><br>
    <a href="home.php?mod=space&amp;do=pm&amp;subop=view&amp;touid=109717">轻云听书最新版</a>
  </dd>
</dl>
''';
    final items = repo.parsePmListHtml(html);
    expect(items.length, 2);
    expect(items[0].uid, 119603);
    expect(items[0].name, '大佬');
    expect(items[0].time, '2026-7-25 18:33');
    expect(items[0].preview, '大佬ai弄好了么');
    expect(items[1].name, '老王');
  });

  test('私信会话按作者 uid 区分「我」和「对方」，不只依赖昵称链接', () {
    const html = '''
<dl id="pmlist_101" class="bbda cl">
  <dd class="y mtm pm_o"><a href="javascript:;" id="pm_o_101" class="o">菜单</a></dd>
  <dd class="m avt"><a href="home.php?mod=space&amp;uid=2002"><img src="uc_server/avatar.php?uid=2002"></a></dd>
  <dd class="ptm">
    <a href="home.php?mod=space&amp;uid=2002" class="xw1">李四</a> &nbsp;
    <br />
    你好，在吗<br />
    <span class="xg1">2026-10-29 09:00</span>
  </dd>
</dl>
<dl id="pmlist_102" class="bbda cl">
  <dd class="m avt"><a href="home.php?mod=space&amp;uid=1"><img src="uc_server/avatar.php?uid=1"></a></dd>
  <dd class="ptm">
    <span class="xi2 xw1">您</span> &nbsp;
    <br />
    在的<br />
    <span class="xg1">2026-10-29 09:01</span>
  </dd>
</dl>
''';
    final (messages, _, peer) = repo.parsePmMessagesHtml(html, peerUid: 2002, myUid: 1);
    expect(messages.length, 2);
    expect(messages[0].mine, isFalse);
    expect(messages[0].author, '李四');
    expect(messages[0].uid, 2002);
    expect(messages[0].text, '你好，在吗');
    expect(messages[1].mine, isTrue);
    expect(messages[1].text, '在的');
    expect(peer, '李四');
  });

  test('不知道自己的 uid 时，用会话对方 uid 反推消息归属', () {
    const html = '''
<dl id="pmlist_1" class="bbda cl">
  <dd class="m avt"><a href="home.php?mod=space&amp;uid=2002"><img src="a.png"></a></dd>
  <dd class="ptm"><br />对方的话<br /><span class="xg1">2026-10-29 09:00</span></dd>
</dl>
<dl id="pmlist_2" class="bbda cl">
  <dd class="m avt"><a href="home.php?mod=space&amp;uid=1"><img src="b.png"></a></dd>
  <dd class="ptm"><br />我的话<br /><span class="xg1">2026-10-29 09:01</span></dd>
</dl>
''';
    final (messages, _, _) = repo.parsePmMessagesHtml(html, peerUid: 2002);
    expect(messages.map((m) => m.mine).toList(), [false, true]);
  });

  test('私信列表昵称是纯文本时不再回落成 UID', () {
    const html = '''
<dl id="pmlist_0" class="bbda cl">
  <dd class="m avt"><a href="home.php?mod=space&amp;uid=119603"><img src="a.png"></a></dd>
  <dd class="ptm pm_c">
    <div class="o"><input type="checkbox" class="pc" /></div>
    <span class="xi2 xw1">您</span> 对 <span class="xw1">大佬</span> 说：<br />
    大佬ai弄好了么 &nbsp; <br />
    <span class="xg1">2026-7-25 18:33</span>
  </dd>
</dl>
''';
    final items = repo.parsePmListHtml(html);
    expect(items.length, 1);
    expect(items.single.name, '大佬');
  });
}
