import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/recycle_bin.dart';
import 'package:mt_forum/data/forum_repository.dart';

/// 「我的主题」里被删掉的帖子（回收站）不该再占位置。
///
/// Discuz 删除主题只是把 `displayorder` 改成 -1，记录留在原版块里。
/// 各套模板的标记方式不同：
///
/// - 手机模板在标题前拼一个「回收站」标签，于是标题长成
///   「回收站【更新】mt论坛_1.8.8」；
/// - 桌面模板给标题链接加 `class="recy"`（配 `.recy { line-through }`）；
/// - 也有模板单独放一个 `<span class="xg1">回收站</span>`。
///
/// 三种都要认，同时不能误伤「回收站使用说明」这种正常标题。
void main() {
  group('标题前缀', () {
    test('模板拼出来的前缀能认出来', () {
      expect(RecycleBin.hasTitlePrefix('回收站【更新】mt论坛_1.8.8'), isTrue);
      expect(RecycleBin.hasTitlePrefix('回收站 某个帖子'), isTrue);
      expect(RecycleBin.hasTitlePrefix('回收站\u3000某个帖子'), isTrue);
      expect(RecycleBin.hasTitlePrefix('[回收站]某个帖子'), isTrue);
      expect(RecycleBin.hasTitlePrefix('【回收站】某个帖子'), isTrue);
      expect(RecycleBin.hasTitlePrefix('回收站（已删除）某个帖子'), isTrue);
    });

    test('正常标题不误伤', () {
      expect(RecycleBin.hasTitlePrefix('回收站使用说明'), isFalse);
      expect(RecycleBin.hasTitlePrefix('回收站'), isFalse);
      expect(RecycleBin.hasTitlePrefix('【更新】mt论坛_1.9.2'), isFalse);
      expect(RecycleBin.hasTitlePrefix(''), isFalse);
    });

    test('前缀能剥掉，剩下的才是原标题', () {
      expect(RecycleBin.stripTitlePrefix('回收站【更新】mt论坛_1.8.8'), '【更新】mt论坛_1.8.8');
      expect(RecycleBin.stripTitlePrefix('[回收站]某个帖子'), '某个帖子');
      expect(RecycleBin.stripTitlePrefix('【更新】mt论坛_1.9.2'), '【更新】mt论坛_1.9.2');
    });
  });

  group('列表解析', () {
    /// 与手机模板 li.forumlist_li 一致，只保留解析用得上的节点。
    String item(String tid, String title, {String? linkClass, String? extra}) => '''
    <li class="forumlist_li">
      <div class="mmlist_li_box">
        <h2><a href="thread-$tid-1-1.html"${linkClass == null ? '' : ' class="$linkClass"'}>$title</a></h2>
        <div class="list_body">摘要</div>
        ${extra ?? ''}
      </div>
    </li>
    ''';

    test('三种回收站标记都会被跳过', () {
      final html = '''
      <ul>
        ${item('100', '回收站【更新】mt论坛_1.8.8')}
        ${item('101', '【更新】mt论坛_1.9.2')}
        ${item('102', '被删除的帖子', linkClass: 'recy')}
        ${item('103', '另一条被删的', extra: '<span class="xg1">回收站</span>')}
        ${item('104', '正常帖子')}
      </ul>
      ''';

      var raw = 0;
      final items = ForumRepository.parseThreadListForTest(html, onRaw: (value) => raw = value);

      expect(items.map((e) => e.tid), [101, 104]);
      // 页面上本来有 5 条，被筛掉 3 条——上层靠这个数字决定要不要补页。
      expect(raw, 5);
    });

    test('「回收站使用说明」这类正常帖子留着', () {
      final html = '<ul>${item('200', '回收站使用说明')}</ul>';
      final items = ForumRepository.parseThreadListForTest(html);
      expect(items.single.title, '回收站使用说明');
    });

    test('宽松解析同样跳过回收站帖子', () {
      const html = '''
      <div>
        <a href="thread-300-1-1.html">回收站【更新】mt论坛_1.8.3</a>
        <a href="thread-301-1-1.html">正常帖子标题够长</a>
        <a href="thread-302-1-1.html" class="recy">被删掉的主题标题</a>
      </div>
      ''';

      var raw = 0;
      final items = ForumRepository.parseLooseThreadsForTest(html, onRaw: (value) => raw = value);

      expect(items.map((e) => e.tid), [301]);
      expect(raw, 3);
    });
  });
}
