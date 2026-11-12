import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 一条浏览记录。
class BrowseHistoryEntry {
  const BrowseHistoryEntry({
    required this.tid,
    required this.title,
    required this.viewedAt,
    this.boardName = '',
    this.author = '',
    this.cover = '',
    this.postedAt = '',
    this.replies = 0,
    this.views = 0,
  });

  final int tid;
  final String title;

  /// 最后一次打开这条帖子的时间（重复浏览只更新时间，不重复占位）。
  final DateTime viewedAt;
  final String boardName;
  final String author;

  /// 首楼第一张图，用作列表缩略图；没有图时为空。
  final String cover;

  /// 发帖时间（站点原文，例如「昨天 21:03」）。
  final String postedAt;
  final int replies;
  final int views;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tid': tid,
        'title': title,
        'viewedAt': viewedAt.toIso8601String(),
        'boardName': boardName,
        'author': author,
        'cover': cover,
        'postedAt': postedAt,
        'replies': replies,
        'views': views,
      };

  static BrowseHistoryEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final tid = int.tryParse('${value['tid']}');
    if (tid == null || tid <= 0) return null;
    final viewedAt = DateTime.tryParse('${value['viewedAt']}');
    if (viewedAt == null) return null;
    String text(String key) => '${value[key] ?? ''}'.trim();
    int number(String key) => int.tryParse('${value[key]}') ?? 0;
    return BrowseHistoryEntry(
      tid: tid,
      title: text('title').isEmpty ? '未命名帖子' : text('title'),
      viewedAt: viewedAt,
      boardName: text('boardName'),
      author: text('author'),
      cover: text('cover'),
      postedAt: text('postedAt'),
      replies: number('replies'),
      views: number('views'),
    );
  }
}

/// 本地浏览历史：打开过的帖子按最近浏览时间倒序保存。
///
/// 只存展示用的元信息（标题、版块、作者、缩略图），不缓存正文，
/// 点进去仍然走正常请求，避免历史占据大量空间或展示过期内容。
class BrowseHistory {
  BrowseHistory({Future<Directory> Function()? directory})
      : _resolveDirectory = directory ?? _defaultDirectory;

  /// 全局实例，界面与帖子页共用。
  static BrowseHistory instance = BrowseHistory();

  /// 最多保留多少条，超出后丢弃最旧的。
  static const int maxEntries = 300;

  /// 数据变化时自增，列表页据此刷新。
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Future<Directory> Function() _resolveDirectory;
  List<BrowseHistoryEntry>? _cache;
  Future<void> _pending = Future<void>.value();

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/history');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file() async => File('${(await _resolveDirectory()).path}/browse_history.json');

  Future<List<BrowseHistoryEntry>> _read() async {
    final cached = _cache;
    if (cached != null) return List<BrowseHistoryEntry>.of(cached);
    final file = await _file();
    final items = <BrowseHistoryEntry>[];
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          for (final value in decoded) {
            final entry = BrowseHistoryEntry.fromJson(value);
            if (entry != null) items.add(entry);
          }
        }
      } catch (error) {
        debugPrint('Unable to read browse history: $error');
      }
    }
    items.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    _cache = items;
    return List<BrowseHistoryEntry>.of(items);
  }

  Future<void> _write(List<BrowseHistoryEntry> items) async {
    _cache = List<BrowseHistoryEntry>.of(items);
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
    revision.value++;
  }

  /// 串行化写入，避免连续打开多个帖子时互相覆盖。
  Future<void> _serial(Future<void> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.catchError((Object error) {
      debugPrint('Browse history write failed: $error');
    });
    return next;
  }

  Future<List<BrowseHistoryEntry>> list() => _read();

  /// 记一条浏览。同一个 tid 只保留一条，重复浏览会刷新时间并置顶。
  Future<void> record({
    required int tid,
    required String title,
    String boardName = '',
    String author = '',
    String cover = '',
    String postedAt = '',
    int replies = 0,
    int views = 0,
    DateTime? viewedAt,
  }) {
    if (tid <= 0) return Future<void>.value();
    return _serial(() async {
      final items = await _read();
      items.removeWhere((entry) => entry.tid == tid);
      items.insert(
        0,
        BrowseHistoryEntry(
          tid: tid,
          title: title.trim().isEmpty ? '未命名帖子' : title.trim(),
          viewedAt: viewedAt ?? DateTime.now(),
          boardName: boardName,
          author: author,
          cover: cover,
          postedAt: postedAt,
          replies: replies,
          views: views,
        ),
      );
      if (items.length > maxEntries) items.removeRange(maxEntries, items.length);
      await _write(items);
    });
  }

  Future<void> remove(int tid) => _serial(() async {
        final items = await _read();
        final before = items.length;
        items.removeWhere((entry) => entry.tid == tid);
        if (items.length == before) return;
        await _write(items);
      });

  Future<void> clear() => _serial(() async {
        final items = await _read();
        if (items.isEmpty) return;
        await _write(<BrowseHistoryEntry>[]);
      });
}
