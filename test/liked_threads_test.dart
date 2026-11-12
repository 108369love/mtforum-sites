import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 已赞状态的本地记录。
///
/// Discuz 的 recommend 只写不读，站点模板也不一定给出可识别的「已赞」标记，
/// 只能靠本机记住：不然退出重进就变回未赞，点一下又收到「已经赞过」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('点赞写进本机，取消后清掉', () async {
    final state = AppState.instance;
    await state.markThreadLiked(910001, true);
    expect(state.isThreadLiked(910001), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('mt_forum_liked_threads'), contains('910001'));

    await state.markThreadLiked(910001, false);
    expect(state.isThreadLiked(910001), isFalse);
    expect(prefs.getStringList('mt_forum_liked_threads'), isNot(contains('910001')));
  });

  test('重复记录不会堆重复项', () async {
    final state = AppState.instance;
    await state.markThreadLiked(910002, true);
    await state.markThreadLiked(910002, true);

    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('mt_forum_liked_threads') ?? const <String>[];
    expect(ids.where((id) => id == '910002'), hasLength(1));
  });
}
