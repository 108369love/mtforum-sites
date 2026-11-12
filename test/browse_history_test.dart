import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/services/browse_history.dart';

void main() {
  late Directory dir;
  late BrowseHistory history;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mt_history_test');
    history = BrowseHistory(directory: () async => dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('记录后按浏览时间倒序返回', () async {
    final base = DateTime(2026, 10, 30, 12);
    await history.record(tid: 168143, title: '逆向实录（下）', viewedAt: base);
    await history.record(tid: 175647, title: '视频演示帖', viewedAt: base.add(const Duration(hours: 2)));

    final items = await history.list();
    expect(items.map((e) => e.tid).toList(), [175647, 168143]);
    expect(items.first.title, '视频演示帖');
  });

  test('重复浏览同一帖子只保留一条，并刷到最前', () async {
    final base = DateTime(2026, 10, 30, 12);
    await history.record(tid: 1, title: '旧标题', viewedAt: base);
    await history.record(tid: 2, title: '另一个帖子', viewedAt: base.add(const Duration(minutes: 5)));
    await history.record(tid: 1, title: '新标题', viewedAt: base.add(const Duration(minutes: 10)));

    final items = await history.list();
    expect(items.length, 2);
    expect(items.first.tid, 1);
    expect(items.first.title, '新标题');
    expect(items.last.tid, 2);
  });

  test('空标题回退为占位文案，非法 tid 不写入', () async {
    await history.record(tid: 0, title: '不该出现');
    await history.record(tid: -3, title: '也不该出现');
    await history.record(tid: 9, title: '   ');

    final items = await history.list();
    expect(items.length, 1);
    expect(items.single.tid, 9);
    expect(items.single.title, '未命名帖子');
  });

  test('超过上限时丢弃最旧的记录', () async {
    final base = DateTime(2026, 1, 1);
    final seed = <Map<String, dynamic>>[
      for (var i = 0; i < BrowseHistory.maxEntries + 5; i++)
        BrowseHistoryEntry(tid: 1000 + i, title: '帖子 $i', viewedAt: base.add(Duration(minutes: i))).toJson(),
    ];
    await File('${dir.path}/browse_history.json').writeAsString(jsonEncode(seed));

    final fresh = BrowseHistory(directory: () async => dir);
    await fresh.record(tid: 9999, title: '最新', viewedAt: base.add(const Duration(days: 4)));

    final items = await fresh.list();
    expect(items.length, BrowseHistory.maxEntries);
    expect(items.first.tid, 9999);
    // 最旧的 6 条（1000~1005）被挤出。
    expect(items.any((e) => e.tid == 1005), isFalse);
    expect(items.any((e) => e.tid == 1006), isTrue);
  });

  test('删除单条与清空', () async {
    await history.record(tid: 1, title: 'A');
    await history.record(tid: 2, title: 'B');
    await history.remove(1);
    expect((await history.list()).map((e) => e.tid), [2]);

    await history.clear();
    expect(await history.list(), isEmpty);
  });

  test('写入落到磁盘，新实例能读回同样内容', () async {
    await history.record(
      tid: 168143,
      title: '逆向实录',
      boardName: '逆向',
      author: 'Bin',
      cover: 'https://icdn.binmt.cc/a.jpeg',
      postedAt: '昨天 21:03',
      replies: 26,
      views: 3120,
    );

    final reopened = BrowseHistory(directory: () async => dir);
    final items = await reopened.list();
    expect(items.single.tid, 168143);
    expect(items.single.boardName, '逆向');
    expect(items.single.author, 'Bin');
    expect(items.single.cover, 'https://icdn.binmt.cc/a.jpeg');
    expect(items.single.replies, 26);
    expect(items.single.views, 3120);
    expect(items.single.postedAt, '昨天 21:03');
  });

  test('文件损坏时按空历史处理，不抛异常', () async {
    await File('${dir.path}/browse_history.json').writeAsString('{not json');
    final broken = BrowseHistory(directory: () async => dir);
    expect(await broken.list(), isEmpty);

    // 仍可继续写入。
    await broken.record(tid: 7, title: '损坏后新增');
    expect((await broken.list()).single.tid, 7);
  });

  test('revision 在数据变化时自增', () async {
    final before = history.revision.value;
    await history.record(tid: 5, title: 'x');
    expect(history.revision.value, before + 1);
    await history.clear();
    expect(history.revision.value, before + 2);
    // 清空一个本来就空的列表不再触发。
    await history.clear();
    expect(history.revision.value, before + 2);
  });
}
