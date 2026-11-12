# MT论坛 客户端

MT论坛（bbs.binmt.cc）的 Flutter 原生客户端。基于 Discuz 移动端页面解析，不使用 WebView 套壳。

## 功能

- 首页信息流：最新 / 回复 / 热门 / 精华，官方公告
- 版块分类与版块主题列表
- 帖子详情：原生富文本渲染、楼层分页、图片查看、回复、收藏、分享
- 消息提醒：我的帖子 / 坛友互动 / 系统提醒 / 应用提醒，提醒直达帖子、用户或私信
- 登录、搜索、发帖
- 站点切换：MT论坛（原生解析）/ XDA Forums、妖火网（内置浏览器）/ 自定义站点，见 [docs/SITES.md](docs/SITES.md)
- 我的：资料、我的主题 / 回复 / 收藏、我的关注 / 我的粉丝、主题切换、关于
- Cookie 本地持久化；纯 Dart 实现站点 `acw_sc__v2` 安全校验

## 目录结构

```
lib/
  core/       配置、站点表、HTTP 会话、WAF 求解、主题
  data/       模型与 Discuz 页面解析
  state/      全局状态
  ui/pages/   页面
  ui/widgets/ 通用组件与帖子 HTML 渲染
```

## 本地构建

```bash
flutter pub get
flutter build apk --release              # 通用包
flutter build apk --release --target-platform android-arm64  # arm64 单架构
```

产物位于 `build/app/outputs/flutter-apk/`。

## 云端构建

推送到 `main`、推 `v*` 标签或手动触发 `Build APK` workflow，都会构建 APK，产物有两条出口：

1. Actions 运行页的 Artifacts（需登录，保留 90 天）；
2. GitHub Releases（公开下载，长期保留）。

`main` 上的构建会先把 `pubspec.yaml` 的 patch 号 +1，Release 的 tag 就用这个版本号
（如 `v2.2.6`）；推 `v*` 标签时则用标签名本身。同一版本重复构建只更新同一个 Release
的附件，不会堆出一串同名版本。

```bash
git tag v2.2.6
git push origin v2.2.6
```

## 签名与 fork

APK 的签名证书决定了能不能覆盖安装。本仓库的 CI 按下面的顺序取签名：

1. 仓库 Secret 里的 `ANDROID_KEYSTORE_BASE64`（正式发布用，长期固定）；
2. 没有 Secret 时，用 Actions 缓存里的备用签名 `mtforum-fallback-keystore-v1`；
3. 缓存也没有，就现生成一张并写回缓存，之后的构建继续用它。

**fork 本仓库**：GitHub 不会把 Secret 带到 fork 里，所以走的是第 2、3 条。第一次构建会生成
一张属于你自己仓库的证书并缓存，此后你自己打的所有包都能互相覆盖。缓存被清理（长期不构建）
后会重新生成，届时需要卸载一次。

想给自己 fork 一份独立、长期固定的正式签名，跑一次：

```bash
tool/setup_signing.sh            # 自动识别当前仓库，生成密钥并写入 4 条 Secret
```

也可以传入已有的 keystore：`KEYSTORE=my.jks KEYSTORE_PASSWORD=xxx tool/setup_signing.sh`。

注意：包名是 `cc.binmt.mt_forum`，和官方包一致，**签名不同就无法共存**，从官方版换到自建
版（或反过来）必须先卸载。

## 说明

- 站点可能更新前端模板或安全校验，如解析失效请对照 `lib/data/forum_repository.dart` 调整选择器。
