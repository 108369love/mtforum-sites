import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';

/// 等级页解析：用站点真实返回的片段做回归。
void main() {
  const html = '''
<div class="comiis_bodybox">
  <div class="comiis_levhead b_b">
    <div class="user_img"><img src="https://cdn.binmt.cc/uc_server/data/avatar/000/03/42/73_avatar_middle.jpg"/></div>
    <h2 class="f_b">我的等级: 硕士生</h2>
    <div class="lev_x comiis_flex">
      <em class="f_c">Lv.6</em>
      <span class="flex bg_b"><em class="z bg_0" style="width:71.3%;"></em></span>
      <em class="f_c">Lv.7</em>
    </div>
    <h3 class="f_c">还需要 <span class="f_a">2874</span> 积分升级到 博士生</h3>
  </div>
  <div class="comiis_levshow bg_f">
    <table>
      <tr><th>我的等级</th><td>硕士生</td></tr>
      <tr><th>积分</th><td>7125</td></tr>
      <tr><th>用户级别</th><td><span class="levico">Lv.6</span></td></tr>
      <tr><th>访问论坛</th><td> <i class="comiis_font f_wx"></i> </td></tr>
      <tr><th>阅读权限</th><td> 90 </td></tr>
      <tr><th>发帖不受限制</th><td> <i class="comiis_font f_g"></i> </td></tr>
    </table>
  </div>
</div>
''';

  test('等级、进度和升级提示', () {
    final info = ForumRepository.parseUserGroup(html);
    expect(info, isNotNull);
    expect(info!.name, '硕士生');
    expect(info.level, 'Lv.6');
    expect(info.nextLevel, 'Lv.7');
    expect(info.nextName, '博士生');
    expect(info.credits, '7125');
    expect(info.remaining, 2874);
    expect(info.progress, closeTo(0.713, 0.001));
  });

  test('权限行：图标型转成有/无，文本型保留原值', () {
    final info = ForumRepository.parseUserGroup(html)!;
    final byName = {for (final p in info.permissions) p.name: p};
    expect(byName['访问论坛']!.allowed, isTrue);
    expect(byName['发帖不受限制']!.allowed, isFalse);
    expect(byName['阅读权限']!.allowed, isNull);
    expect(byName['阅读权限']!.value, '90');
    // 头部已经展示过等级和积分，表格里不该重复。
    expect(byName.containsKey('我的等级'), isFalse);
    expect(byName.containsKey('积分'), isFalse);
  });

  test('没登录时页面没有等级头，返回 null', () {
    expect(ForumRepository.parseUserGroup('<div>请先登录</div>'), isNull);
  });
}
