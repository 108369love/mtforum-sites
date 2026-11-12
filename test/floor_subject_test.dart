import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;
import 'package:mt_forum/data/forum_repository.dart';

/// Discuz 给回复存了 subject，编辑过的回复会变成 `Re: 主题名`，
/// 网页端在正文上方渲染一行标题。楼层卡片里这行是重复信息，要删掉。
void main() {
  Element content(String html) => parser.parseFragment(html).children.first;

  test('删掉正文顶上的 Re: 标题，正文保留', () {
    final el = content(
      '<div class="comiis_messages"><h2>Re: mt论坛软件端</h2>'
      '<div class="comiis_edit">本帖最后由 Aiopr·皇者 于 2026-10-29 14:36 编辑</div>'
      '<p>修复了个bug，请下载最新版</p></div>',
    );

    ForumRepository.removeFloorSubject(el);

    expect(el.text.contains('Re:'), isFalse);
    expect(el.text.contains('修复了个bug'), isTrue);
    expect(el.text.contains('本帖最后由'), isTrue);
  });

  test('正文里自己写的小标题不动', () {
    final el = content('<div><h2>更新日志</h2><p>正文</p></div>');

    ForumRepository.removeFloorSubject(el);

    expect(el.text.contains('更新日志'), isTrue);
  });

  test('类名标记的楼层标题也能删', () {
    final el = content(
      '<div><div class="comiis_edit">本帖最后由 A 于 2026-10-29 14:36 编辑</div>'
      '<div class="comiis_subject">Re: mt论坛软件端</div><p>正文</p></div>',
    );

    ForumRepository.removeFloorSubject(el);

    expect(el.text.contains('Re:'), isFalse);
    expect(el.text.contains('正文'), isTrue);
  });

  test('全角冒号同样识别', () {
    final el = content('<div><h3>Re：mt论坛软件端</h3><p>正文</p></div>');

    ForumRepository.removeFloorSubject(el);

    expect(el.text.contains('mt论坛软件端'), isFalse);
  });

  test('普通回复没有被塞标题时什么都不做', () {
    final el = content('<div><p>感谢分享</p></div>');

    ForumRepository.removeFloorSubject(el);

    expect(el.text.contains('感谢分享'), isTrue);
  });
}
