import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/http_session.dart';
import '../core/sign_in_status.dart';
import '../data/forum_repository.dart';
import '../data/models.dart';

class AppState extends ChangeNotifier {
  AppState._();

  static final AppState instance = AppState._();

  static const String _themeKey = 'mt_forum_theme';
  static const String _themeSeedKey = 'mt_forum_theme_seed';
  static const String _readLinkColorKey = 'mt_forum_read_link_color';
  static const String _readHintColorKey = 'mt_forum_read_hint_color';
  static const String _floatingGlassNavKey = 'mt_forum_floating_glass_nav';
  static const String _floatingGlassNavOpacityKey = 'mt_forum_floating_glass_nav_opacity';
  static const String _floatingGlassNavBlurKey = 'mt_forum_floating_glass_nav_blur';
  static const String _composeGlassOpacityKey = 'mt_forum_compose_glass_opacity';
  static const String _composeGlassBlurKey = 'mt_forum_compose_glass_blur';
  static const String _threadGlassOpacityKey = 'mt_forum_thread_glass_opacity';
  static const String _threadGlassBlurKey = 'mt_forum_thread_glass_blur';
  static const String _autoSignInDateKey = 'mt_forum_auto_signin_date';

  /// 本机点过赞的主题 id（最多保留 200 条）。
  ///
  /// Discuz 的 recommend 只写不读，页面模板也未必把「已赞」渲染成可识别的
  /// class，所以进入帖子时没法和站点核对状态。与其每次都显示未赞、点一下
  /// 再收到「已评价过」，不如把本机的操作记下来，退出重进仍显示已赞。
  static const String _likedThreadsKey = 'mt_forum_liked_threads';
  static const int _likedThreadsLimit = 200;
  final List<int> _likedThreads = <int>[];
  bool _autoSignInRunning = false;
  String? _autoSignInAttemptDate;

  /// 已确认签到成功的自然日（本地缓存），配合 [signedInToday] 给「我的」卡片用。
  String? _signInDay;

  /// 手动签到进行中，用来在卡片上转圈、防连点。
  bool signingIn = false;

  final ForumRepository repo = ForumRepository.instance;
  final HttpSession session = HttpSession.instance;

  ThemeMode themeMode = ThemeMode.system;
  Color themeSeedColor = const Color(0xFF607080);

  /// 正文配色：`null` 表示跟随主题。
  ///
  /// 论坛帖子动辄几百行，链接和「回复可见」这类提示混在正文里，默认色和
  /// 正文太接近，长文里很容易划过去。给色弱用户留一个自己挑颜色的口子。
  Color? readLinkColor;
  Color? readHintColor;
  bool floatingGlassNav = false;
  double floatingGlassNavOpacity = 0.25;
  double floatingGlassNavBlur = 30.0;

  /// 悬浮玻璃底栏实测占用的屏幕高度（含底部安全区），由 AppShell 量出来。
  ///
  /// 各页面的列表末尾都要补这么高。写死常数会被系统字号带偏：字号调大，
  /// 胶囊跟着变高，补少了最后一张卡片就被压进玻璃里。
  double floatingNavHeight = 0;

  /// 发帖悬浮按钮的液态玻璃外观：透明度与背景模糊度。
  double composeGlassOpacity = 0.28;
  double composeGlassBlur = 26.0;

  /// 帖子页顶栏、底部回复框、右上角菜单的液态玻璃外观。
  ///
  /// 这三处共用一套参数：它们同处一个页面，观感必须一致，
  /// 分开调反而容易调出「顶栏很透、回复框很实」的割裂感。
  double threadGlassOpacity = 0.55;
  double threadGlassBlur = 22.0;
  UserProfile? profile;
  bool localReady = false;
  bool profileLoading = false;
  String? profileError;

  List<ForumCategory>? _boards;
  List<ThreadSummary>? _announcements;

  bool get isLoggedIn => session.hasLoginCookie;

  /// 本机是否记着这条主题已赞。
  bool isThreadLiked(int tid) => _likedThreads.contains(tid);

  /// 记录或清除一条主题的已赞状态。
  ///
  /// 只写失败也不该影响点赞本身，所以这里吞掉异常：界面状态已经更新过了。
  Future<void> markThreadLiked(int tid, bool liked) async {
    _likedThreads.remove(tid);
    if (liked) {
      _likedThreads.add(tid);
      if (_likedThreads.length > _likedThreadsLimit) {
        _likedThreads.removeRange(0, _likedThreads.length - _likedThreadsLimit);
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_likedThreadsKey, _likedThreads.map((id) => '$id').toList());
    } catch (_) {
      // 本地记录丢了顶多下次显示未赞，不影响点赞结果。
    }
  }

  /// 今天是否已经签到。未登录时没有意义，卡片也不显示。
  bool get signedInToday => signedInOn(_signInDay, DateTime.now());

  Future<void> bootstrapLocal() async {
    await repo.init();
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getString(_themeKey);
    themeSeedColor = Color(prefs.getInt(_themeSeedKey) ?? 0xFF607080);
    final linkColor = prefs.getInt(_readLinkColorKey);
    final hintColor = prefs.getInt(_readHintColorKey);
    readLinkColor = linkColor == null ? null : Color(linkColor);
    readHintColor = hintColor == null ? null : Color(hintColor);
    floatingGlassNav = prefs.getBool(_floatingGlassNavKey) ?? false;
    floatingGlassNavOpacity = (prefs.getDouble(_floatingGlassNavOpacityKey) ?? 0.25).clamp(0.05, 0.65).toDouble();
    floatingGlassNavBlur = (prefs.getDouble(_floatingGlassNavBlurKey) ?? 30.0).clamp(0.0, 40.0).toDouble();
    composeGlassOpacity = (prefs.getDouble(_composeGlassOpacityKey) ?? 0.28).clamp(0.05, 0.75).toDouble();
    composeGlassBlur = (prefs.getDouble(_composeGlassBlurKey) ?? 26.0).clamp(0.0, 40.0).toDouble();
    threadGlassOpacity = (prefs.getDouble(_threadGlassOpacityKey) ?? 0.55).clamp(0.05, 0.85).toDouble();
    threadGlassBlur = (prefs.getDouble(_threadGlassBlurKey) ?? 22.0).clamp(0.0, 40.0).toDouble();
    _signInDay = prefs.getString(_autoSignInDateKey);
    _likedThreads
      ..clear()
      ..addAll(
        (prefs.getStringList(_likedThreadsKey) ?? const <String>[])
            .map(int.tryParse)
            .whereType<int>(),
      );
    themeMode = switch (theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    localReady = true;
    notifyListeners();
    if (isLoggedIn) {
      refreshProfile();
      // 不阻塞首屏；同一自然日成功后持久化日期，重复打开不会重复签到。
      autoSignInOncePerDay();
    }
  }

  /// 登录状态下每日最多自动签到一次。仅在成功（含服务端提示已签到）后记录日期；
  /// 网络失败时不写入日期，下一次启动仍可重试。整个过程不展示提示。
  Future<void> autoSignInOncePerDay() async {
    if (!isLoggedIn || _autoSignInRunning) return;
    final today = signInDayKey(DateTime.now());
    if (_autoSignInAttemptDate == today) return;

    _autoSignInRunning = true;
    _autoSignInAttemptDate = today;
    try {
      final prefs = await SharedPreferences.getInstance();
      // 本地已经有今天的记录：直接认，不必再打一次接口。
      _signInDay ??= prefs.getString(_autoSignInDateKey);
      if (_signInDay == today) {
        notifyListeners();
        return;
      }
      await repo.signIn();
      _signInDay = today;
      await prefs.setString(_autoSignInDateKey, today);
      // 卡片上的「今日未签到」要跟着翻成「已签到」。
      notifyListeners();
    } catch (_) {
      // 静默失败，不打扰用户；未保存日期，下一次启动可重新尝试。
    } finally {
      _autoSignInRunning = false;
    }
  }

  /// 手动签到。返回给用户的提示文案；返回 null 表示正在签到、忽略这次点击。
  Future<String?> signInNow() async {
    if (!isLoggedIn) return '请先登录后再签到';
    if (signedInToday) return '今天已经签过到了';
    if (_autoSignInRunning) return '正在签到，稍等一下';
    if (signingIn) return null;

    signingIn = true;
    notifyListeners();
    try {
      final message = await repo.signIn();
      final today = signInDayKey(DateTime.now());
      _signInDay = today;
      _autoSignInAttemptDate = today;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_autoSignInDateKey, today);
      return message;
    } on SiteException catch (e) {
      return e.message;
    } catch (_) {
      return '签到失败，请稍后重试';
    } finally {
      signingIn = false;
      notifyListeners();
    }
  }

  Future<void> refreshProfile({bool silent = true}) async {
    if (!isLoggedIn) {
      profile = null;
      return;
    }
    profileLoading = true;
    if (!silent) notifyListeners();
    try {
      profile = await repo.fetchMyProfile(fallbackName: profile?.username ?? '');
      profileError = null;
    } on SiteException catch (e) {
      profileError = e.message;
      if (e.message.contains('登录') && e.message.contains('失效')) {
        await repo.logout();
        profile = null;
      }
    } catch (_) {
      profileError = '个人资料加载失败';
    } finally {
      profileLoading = false;
      notifyListeners();
    }
  }

  Future<UserProfile> login(String username, String password, {int questionId = 0, String answer = ''}) async {
    final user = await repo.login(username, password, questionId: questionId, answer: answer);
    profile = user;
    profileError = null;
    _boards = null;
    notifyListeners();
    autoSignInOncePerDay();
    return user;
  }

  Future<void> logout() async {
    await repo.logout();
    profile = null;
    profileError = null;
    _announcements = null;
    // 签到是按账号算的，换号后不能沿用上一个人的「今天已签到」。
    _signInDay = null;
    _autoSignInAttemptDate = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_autoSignInDateKey);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  /// 记录底栏高度。值没变就不通知，避免测量和重建互相触发。
  void setFloatingNavHeight(double height) {
    if (height <= 0 || (height - floatingNavHeight).abs() < 0.5) return;
    floatingNavHeight = height;
    notifyListeners();
  }

  Future<void> setFloatingGlassNav(bool enabled) async {
    floatingGlassNav = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_floatingGlassNavKey, enabled);
  }

  Future<void> setFloatingGlassNavAppearance({required double opacity, required double blur}) async {
    floatingGlassNavOpacity = opacity.clamp(0.05, 0.65).toDouble();
    floatingGlassNavBlur = blur.clamp(0.0, 40.0).toDouble();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_floatingGlassNavOpacityKey, floatingGlassNavOpacity);
    await prefs.setDouble(_floatingGlassNavBlurKey, floatingGlassNavBlur);
  }

  /// 调整发帖悬浮按钮的玻璃透明度与模糊度并持久化。
  Future<void> setComposeGlassAppearance({required double opacity, required double blur}) async {
    composeGlassOpacity = opacity.clamp(0.05, 0.75).toDouble();
    composeGlassBlur = blur.clamp(0.0, 40.0).toDouble();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_composeGlassOpacityKey, composeGlassOpacity);
    await prefs.setDouble(_composeGlassBlurKey, composeGlassBlur);
  }

  /// 调整帖子页三处玻璃的透明度与模糊度并持久化。
  Future<void> setThreadGlassAppearance({required double opacity, required double blur}) async {
    threadGlassOpacity = opacity.clamp(0.05, 0.85).toDouble();
    threadGlassBlur = blur.clamp(0.0, 40.0).toDouble();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_threadGlassOpacityKey, threadGlassOpacity);
    await prefs.setDouble(_threadGlassBlurKey, threadGlassBlur);
  }

  Future<void> setThemeSeedColor(Color color) async {
    themeSeedColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeSeedKey, color.toARGB32());
  }

  /// 正文里的链接颜色。传 `null` 恢复跟随主题色。
  Future<void> setReadLinkColor(Color? color) async {
    readLinkColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(_readLinkColorKey);
    } else {
      await prefs.setInt(_readLinkColorKey, color.toARGB32());
    }
  }

  /// 「回复可见 / 需要回复」这类提示的颜色。传 `null` 恢复默认（琥珀橙）。
  Future<void> setReadHintColor(Color? color) async {
    readHintColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(_readHintColorKey);
    } else {
      await prefs.setInt(_readHintColorKey, color.toARGB32());
    }
  }

  /// 正文链接实际用的颜色。
  Color readLinkColorOf(ColorScheme scheme) => readLinkColor ?? scheme.primary;

  /// 正文里「回复可见」提示实际用的颜色。
  ///
  /// 深色背景上 #E4711B 会发闷，换成更亮的琥珀色，保证在暗底上仍然跳出来。
  Color readHintColorOf(ColorScheme scheme) =>
      readHintColor ??
      (scheme.brightness == Brightness.dark ? const Color(0xFFFFA24D) : const Color(0xFFD2691E));

  /// 直接塞一份版块数据，省掉网络请求。
  ///
  /// 发帖、搜索这类页面的测试只关心表单本身，不需要真去拉一遍版块。
  @visibleForTesting
  void debugSetBoards(List<ForumCategory> value) {
    _boards = value;
    notifyListeners();
  }

  Future<List<ForumCategory>> boards({bool force = false}) async {
    if (!force && _boards != null) return _boards!;
    final value = await repo.fetchBoards();
    _boards = value;
    return value;
  }

  Future<List<ThreadSummary>> announcements({bool force = false}) async {
    if (!force && _announcements != null) return _announcements!;
    final value = await repo.fetchAnnouncements();
    _announcements = value;
    return value;
  }
}
