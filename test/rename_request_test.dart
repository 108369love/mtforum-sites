import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';
import 'package:mt_forum/ui/pages/rename_request_page.dart';

/// 改名申请的回归测试。
///
/// 站点把改名做成了 `nimba_rename` 插件：提交后扣金币、等管理员改名。成功
/// 文案里本身就带「审核」二字，用通用的 `_looksLikeError` 会把成功判成失败，
/// 所以这里单独盯住判定逻辑。
void main() {
  group('提交结果判定', () {
    test('成功文案里带「审核」也算成功', () {
      expect(ForumRepository.renameFailed('改名申请已提交，请等待管理员审核'), isFalse);
      expect(ForumRepository.renameFailed('申请成功，请等待审核'), isFalse);
    });

    test('金币不足', () {
      expect(ForumRepository.renameFailed('抱歉，您的金币不足 200，无法申请改名'), isTrue);
    });

    test('用户名被占用', () {
      expect(ForumRepository.renameFailed('该用户名已被注册，请换一个'), isTrue);
    });

    test('空回包不硬判失败', () {
      expect(ForumRepository.renameFailed(''), isFalse);
    });
  });

  group('提示语提取', () {
    test('showmessage 脚本', () {
      const body = '<root><![CDATA[<script>showmessage(\'申请成功，请等待管理员审核\');</script>]]></root>';
      final message = ForumRepository.renameMessage(body);
      expect(message, contains('申请成功'));
      expect(ForumRepository.renameFailed(message), isFalse);
    });

    test('普通提示页', () {
      const body = '<div class="alert_error">抱歉，您的请求来路不正确</div>';
      final message = ForumRepository.renameMessage(body);
      expect(message, contains('来路不正确'));
      expect(ForumRepository.renameFailed(message), isTrue);
    });
  });

  group('本地校验', () {
    test('新用户名', () {
      expect(RenameRequestPage.validateName('', 'Aiopr·皇者'), isNotNull);
      expect(RenameRequestPage.validateName('Aiopr·皇者', 'Aiopr·皇者'), isNotNull);
      expect(RenameRequestPage.validateName('a', 'Aiopr·皇者'), isNotNull);
      expect(RenameRequestPage.validateName('一二三四五六七八九十一二三四五六', 'Aiopr·皇者'), isNotNull);
      expect(RenameRequestPage.validateName('abc def', 'Aiopr·皇者'), isNotNull);
      expect(RenameRequestPage.validateName('新的名字', 'Aiopr·皇者'), isNull);
      expect(RenameRequestPage.validateName('mt_user01', 'Aiopr·皇者'), isNull);
    });

    test('改名理由限制 20 字', () {
      expect(RenameRequestPage.validateReason(''), isNotNull);
      expect(RenameRequestPage.validateReason('一' * 20), isNull);
      expect(RenameRequestPage.validateReason('一' * 21), isNotNull);
    });
  });
}
