import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/video_link.dart';

void main() {
  group('视频链接识别', () {
    test('B站 BV 号拼出官方播放器', () {
      final v = parseVideoLink('https://www.bilibili.com/video/BV1xx411c7mD?p=2')!;
      expect(v.kind, VideoKind.bilibili);
      expect(v.videoId, 'BV1xx411c7mD');
      expect(v.playUrl, contains('player.bilibili.com/player.html?bvid=BV1xx411c7mD'));
      expect(v.asPage, isFalse);
    });

    test('B站 av 号转成 aid 播放器', () {
      final v = parseVideoLink('https://m.bilibili.com/video/av170001')!;
      expect(v.kind, VideoKind.bilibili);
      expect(v.playUrl, contains('aid=170001'));
    });

    test('B站短链走原页面，仍在内置浏览器播放', () {
      final v = parseVideoLink('https://b23.tv/abc123')!;
      expect(v.kind, VideoKind.bilibili);
      expect(v.asPage, isTrue);
      expect(v.playUrl, 'https://b23.tv/abc123');
    });

    test('已经是播放器地址时原样使用', () {
      final v = parseVideoLink('https://player.bilibili.com/player.html?bvid=BV1xx411c7mD&autoplay=0')!;
      expect(v.kind, VideoKind.bilibili);
      expect(v.videoId, 'BV1xx411c7mD');
      expect(v.playUrl, contains('player.bilibili.com'));
    });

    test('YouTube 各种写法都归一到 embed', () {
      expect(parseVideoLink('https://www.youtube.com/watch?v=dQw4w9WgXcQ')!.playUrl, contains('/embed/dQw4w9WgXcQ'));
      expect(parseVideoLink('https://youtu.be/dQw4w9WgXcQ')!.playUrl, contains('/embed/dQw4w9WgXcQ'));
      expect(parseVideoLink('https://www.youtube.com/shorts/dQw4w9WgXcQ')!.playUrl, contains('/embed/dQw4w9WgXcQ'));
    });

    test('直链视频文件', () {
      final v = parseVideoLink('https://cdn.example.com/demo/clip.mp4')!;
      expect(v.kind, VideoKind.direct);
      expect(v.isDirectFile, isTrue);
      expect(v.playUrl, 'https://cdn.example.com/demo/clip.mp4');
    });

    test('国内常见视频站识别为站点播放', () {
      expect(parseVideoLink('https://www.douyin.com/video/7300000000000000000')!.kind, VideoKind.douyin);
      expect(parseVideoLink('https://v.qq.com/x/page/a1234567.html')!.kind, VideoKind.tencent);
      expect(parseVideoLink('https://www.ixigua.com/7300000000000000000')!.kind, VideoKind.ixigua);
    });

    test('普通链接不算视频', () {
      expect(parseVideoLink('https://bbs.binmt.cc/thread-175647-1-1.html'), isNull);
      expect(parseVideoLink('https://pan.quark.cn/s/abc'), isNull);
      expect(parseVideoLink('ftp://example.com/a.mp4'), isNull);
      expect(parseVideoLink(''), isNull);
    });
  });

  group('正文里单独成段的视频链接', () {
    test('带说明前缀也能识别', () {
      final v = parseStandaloneVideo('视频演示：https://www.bilibili.com/video/BV1xx411c7mD');
      expect(v, isNotNull);
      expect(v!.kind, VideoKind.bilibili);
    });

    test('链接前后有其他句子时不卡片化', () {
      expect(
        parseStandaloneVideo('这个功能我做了很久，演示看 https://www.bilibili.com/video/BV1xx411c7mD 后面还有别的说明'),
        isNull,
      );
    });

    test('普通文本不误判', () {
      expect(parseStandaloneVideo('今天更新了 1.6.9 版本'), isNull);
      expect(parseStandaloneVideo('下载地址 https://bbs.binmt.cc/thread-1-1-1.html'), isNull);
    });
  });
}
