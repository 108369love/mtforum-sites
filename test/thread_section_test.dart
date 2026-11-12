import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/pages/thread_page.dart';

/// 「评论区」是第 1 页里主题正文与回复之间的分隔。
/// 第 2 页整页都是回复，再插一次就会卡在 11 楼和 12 楼中间。
void main() {
  test('第一页主题正文之后出现评论区标题', () {
    expect(
      ThreadPage.needsSectionHeader(page: 1, onlyOp: false, postCount: 11, firstPostIsOp: true),
      isTrue,
    );
  });

  test('第二页及以后都是回复，不再插评论区标题', () {
    // 截图里的场景：第 2 页 11、12、13 楼。
    expect(
      ThreadPage.needsSectionHeader(page: 2, onlyOp: false, postCount: 3, firstPostIsOp: false),
      isFalse,
    );
    expect(
      ThreadPage.needsSectionHeader(page: 3, onlyOp: false, postCount: 10, firstPostIsOp: false),
      isFalse,
    );
  });

  test('只看楼主、只有一楼、倒序时都不插标题', () {
    expect(
      ThreadPage.needsSectionHeader(page: 1, onlyOp: true, postCount: 6, firstPostIsOp: true),
      isFalse,
    );
    expect(
      ThreadPage.needsSectionHeader(page: 1, onlyOp: false, postCount: 1, firstPostIsOp: true),
      isFalse,
    );
    // 倒序 / 按作者筛选时首项不是主题正文。
    expect(
      ThreadPage.needsSectionHeader(page: 1, onlyOp: false, postCount: 10, firstPostIsOp: false),
      isFalse,
    );
  });
}
