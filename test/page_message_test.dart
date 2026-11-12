import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/page_message.dart';

/// 编辑页的「本帖最后由 … 编辑」记录和真正的错误提示共用 `.alert_info`，
/// 早先保存修改后会被当成错误，导致停在编辑页不回帖子。
void main() {
  test('识别编辑记录', () {
    const text = '本帖最后由 Aiopr·皇者 于 2026-10-31 17:32 编辑 '
        '更新内容：增加签到状态显示，修复部分bug 只要登录了每天打开一次软件就会自动签到';
    expect(isEditNote(text), isTrue);
  });

  test('前面有空白也算', () {
    expect(isEditNote('  本帖最后由 某人 于 2026-01-01 10:00 编辑'), isTrue);
  });

  test('真正的提示不被误杀', () {
    expect(isEditNote('抱歉，您的帖子小于 10 个字符的限制'), isFalse);
    expect(isEditNote('编辑帖子成功'), isFalse);
    expect(isEditNote(''), isFalse);
  });
}
