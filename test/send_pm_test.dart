import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';

/// 私信结果判定的回归测试。
///
/// `inajax=1` 的响应是 succeedhandle_pm / errorhandle_pm 脚本，
/// 页面上那些提示容器一个都匹配不上。早先拿页面消息去读，读到的永远是
/// 空，于是私信没发出去也会提示「已发送」。
void main() {
  test('succeedhandle = 已发送', () {
    const body = '<root><![CDATA[<script>succeedhandle_pm(\'发送成功\');</script>]]></root>';
    expect(ForumRepository.sendPmFailure(body), isNull);
  });

  test('errorhandle = 失败，并把服务端原话带出来', () {
    const body = '<root><![CDATA[<script>errorhandle_pm(\'抱歉，您不能给自己发短消息\');</script>]]></root>';
    final failure = ForumRepository.sendPmFailure(body);
    expect(failure, isNotNull);
    expect(failure, contains('不能给自己发短消息'));
  });

  test('普通页面上的错误提示也能认出', () {
    const body = '<div class="alert_error">抱歉，您的请求来路不正确</div>';
    expect(ForumRepository.sendPmFailure(body), isNotNull);
  });

  test('空白响应不当成功，也不硬说失败', () {
    // 站点偶尔回空包，这种情况交给调用方按「已发送」处理，
    // 不能凭空造一个错误出来。
    expect(ForumRepository.sendPmFailure(''), isNull);
  });
}
