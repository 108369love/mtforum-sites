import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';

/// 私信列表摘要的解析回归测试。
///
/// 线上问题：列表里每条会话的预览后面都拖着一串
/// 「删除 忽略 共 2 条 菜单 | 回复」。
///
/// 这段是 Discuz 的会话操作区（`span.pm_o`）：删除 / 忽略 放在
/// `display:none` 的下拉层里，菜单是只认 JS 的悬浮按钮，网页端靠 CSS
/// 摆到右侧、鼠标移上去才出现。App 只读 DOM，看不到这层「视觉上不显示」，
/// 于是把整排操作词当成正文摘要的一部分。
void main() {
  final repo = ForumRepository.instance;

  /// 与 Discuz X3.5 `template/default/home/space_pm.htm` 里的
  /// 私信会话列表结构一致，只删掉了无关的 checkbox 属性。
  const listHtml = '''
<dl id="pmlist_5" class="bbda cur1 cl newpm">
  <dd class="m avt">
    <div class="newpm_avt" title="新私信"></div>
    <a href="home.php?mod=space&amp;uid=119603"><img src="uc_server/avatar.php?uid=119603"></a>
  </dd>
  <dd class="ptm pm_c">
    <div class="o"><input type="checkbox" name="deletepm_deluid[]" class="pc" value="119603" /></div>
    <a href="home.php?mod=space&amp;uid=119603" target="_blank" class="xw1">康哥</a> 对 <span class="xi2">您</span> 说：<br />
    康哥开源了也不行吗 &nbsp;  <br />
    <span class="xg1">2026-11-01 09:52</span> &nbsp;
    <span class="pm_o y">
      <div id="pm_o_5_menu" class="p_pop" style="display: none;">
        <ul>
          <li><a href="javascript:;" onclick="ajaxget('...')">删除</a></li>
          <li><a href="home.php?mod=spacecp&amp;ac=pm&amp;op=pm_ignore" id="a_feed_menu_5">忽略</a></li>
        </ul>
      </div>
      <span class="xg1 z">共 2 条</span>
      <a href="javascript:;" id="pm_o_5" class="o" onmouseover="showMenu({...})">菜单</a>
       |
      <a href="home.php?mod=space&amp;do=pm&amp;subop=view&amp;touid=119603#last" id="pmlist_5_a">回复</a>
    </span>
  </dd>
</dl>
''';

  test('私信摘要不带上「删除 忽略 共 N 条 菜单 | 回复」这排操作', () {
    final items = repo.parsePmListHtml(listHtml);
    expect(items.length, 1);
    final item = items.single;
    expect(item.uid, 119603);
    expect(item.name, '康哥');
    expect(item.preview, '康哥开源了也不行吗');
    for (final noise in ['删除', '忽略', '共 2 条', '菜单', '回复']) {
      expect(item.preview.contains(noise), isFalse, reason: '摘要把「$noise」也带出来了');
    }
  });

  test('会话内页的消息同样不混入操作区文字', () {
    const chatHtml = '''
<dl id="pmlist_501" class="bbda cl">
  <dd class="m avt"><a href="home.php?mod=space&amp;uid=2002"><img src="uc_server/avatar.php?uid=2002"></a></dd>
  <dd class="ptm pm_c">
    <div class="o"><input type="checkbox" class="pc" /></div>
    <a href="home.php?mod=space&amp;uid=2002" class="xw1">李四</a> 对 <span class="xi2">您</span> 说：<br />
    你好，在吗<br />
    <span class="xg1">2026-10-31 09:00</span> &nbsp;
    <span class="pm_o y">
      <div id="pm_o_501_menu" class="p_pop" style="display: none;"><ul><li><a href="javascript:;">删除</a></li></ul></div>
      <span class="xg1 z">共 3 条</span>
      <a href="javascript:;" id="pm_o_501" class="o">菜单</a> | <a href="x">回复</a>
    </span>
  </dd>
</dl>
''';
    final (messages, _, _) = repo.parsePmMessagesHtml(chatHtml, peerUid: 2002, myUid: 1);
    expect(messages.length, 1);
    expect(messages.single.text, '你好，在吗');
  });

  test('主题把 pm_o 拿来装正文时不会被当成操作区吞掉', () {
    const themedHtml = '''
<dl id="pmlist_9" class="bbda cl">
  <dd class="m avt"><a href="home.php?mod=space&amp;uid=3003"><img src="a.png"></a></dd>
  <dd class="ptm pm_c">
    <span class="xi2 xw1">您</span> 对 <a href="home.php?mod=space&amp;uid=3003" class="xw1">老王</a> 说：<br />
    <span class="pm_o y">附件已经发到你邮箱了，注意查收</span>
  </dd>
</dl>
''';
    final items = repo.parsePmListHtml(themedHtml);
    expect(items.single.preview, '附件已经发到你邮箱了，注意查收');
  });
}
