import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/reply_notice.dart';

/// 回复某楼时正文顶部那条引用框。
///
/// 正常路径用服务端回复页上的 `noticetrimstr`（见 reply_context_test），
/// 这里测的是取不到时的兜底格式。
void main() {
  test('兜底引用条带上作者、时间、pid 与 tid', () {
    final notice = buildReplyNotice(
      author: 'Aioprh',
      time: '2026-10-29 00:57',
      pid: 12345,
      tid: 678,
    );
    expect(notice, startsWith('[quote]'));
    expect(notice, endsWith('[/quote]'));
    expect(notice, contains('Aioprh 发表于 2026-10-29 00:57'));
    expect(notice, contains('pid=12345'));
    expect(notice, contains('ptid=678'));
    // 和网页端一样不带原文，只有抬头。
    expect('[/quote]'.allMatches(notice).length, 1);
  });

  test('作者为空时不留空白，没有时间就不写「发表于」', () {
    final notice = buildReplyNotice(author: '  ', pid: 1, tid: 2);
    expect(notice, contains('该楼'));
    expect(notice, isNot(contains('发表于')));
    expect(notice, isNot(contains('  ')));
  });

  test('正文只提交用户输入，引用条走 noticetrimstr，不再本地拼接', () {
    final source = File('lib/ui/pages/thread_page.dart').readAsStringSync();
    // 本地拼 quote 再塞进正文会让服务端前插一次，网页端出现两段引用。
    expect(source.contains('_startQuote'), isFalse);
    expect(source.contains('_hiddenQuotePayload'), isFalse);
    expect(source.contains('composeReplyMessage'), isFalse);
  });
}
