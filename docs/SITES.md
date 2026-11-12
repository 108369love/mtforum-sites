# 站点切换与第三方站点适配

本客户端原来只会打开一个站点：`bbs.binmt.cc`（Discuz，原生解析）。这一版加了
「站点」这一层抽象：站点可以切换，也可以自己加。

## 怎么用

- 原生界面：**我的 → 站点**，在列表里选。
- 内置浏览器里：右上角 **⋮ → 切换站点**。
- 自定义站点：**我的 → 站点 → 自定义站点**，填站点根地址（`https://` 可省略）。

选择会写进 `SharedPreferences`（键 `mt_forum_site_id`，自定义地址另存
`mt_forum_site_custom`），下次启动直接进上次的站点。

## 内置站点

| 站点 | 接入方式 | 说明 |
| --- | --- | --- |
| MT论坛（`bbs.binmt.cc`） | 原生 | Discuz 移动端模板解析，发帖/回复/私信/提醒都是原生页面 |
| XDA Forums（`xdaforums.com`） | 内置浏览器 | XenForo 站点，跑站点自己的前端，应用只补壳层 |
| 妖火网（`yaohuo.me`） | 内置浏览器 | ASP.NET 站点，全部内容需登录且带人机验证，只能由浏览器完成登录 |

## XDA 为什么走内置浏览器，而不是像 MT论坛 那样解析

不是偷懒，是抓不到。`xdaforums.com` 整站在 **Bunny Shield** 后面：任何非浏览器
请求（包括 `/`、`/forums/...`、`/forums/-/index.rss`，甚至带 Googlebot UA）都会收到
一个 `403` 挑战页，页面里没有任何帖子内容，只有一段要执行的 JS：

```html
<body data-pow="<userkey>#<challenge>#...">
<script src="/.bunny-shield/assets/shield-challenge.js"></script>
```

那段 JS 会用 Web Worker + WASM 跑 **Argon2**（`time=2, mem=512, hashLen=32`，
13 bit 难度）算出答案，`POST /.bunny-shield/verify-pow` 拿到 Cookie 之后才放行。
纯 Dart 的 `http` 客户端要自己实现 Argon2 + 这套握手，而且站点随时能改难度；
即便过了挑战，XenForo 的模板和 Discuz 完全是两套结构，`forum_repository.dart`
里那 5000 行 Discuz 解析器一行都用不上。

所以这里的选择是：**让站点自己的前端跑起来**，应用只负责壳层。

## 内置浏览器这一版做了什么

- 移动端 UA（XenForo 按 UA 出响应式模板），第三方 Cookie 打开（挑战页要读写
  `bunny.net` / CDN 域下的存储，关掉会卡在挑战上）。
- 顶栏：站点名 + 当前地址、刷新、外部浏览器打开、⋮（切换站点 / 复制链接 / 清除站点数据）。
- 底部快捷入口：首页 / 版块 / 搜索 / 我的（都是 XenForo 的标准路由 `/`、`/forums/`、
  `/search/`、`/account/`）。
- 返回手势先退网页、退到底再退应用；预测性返回的判断和网页历史同步。
- 注入一小段样式与脚本（`_tweakScript`）：收掉「打开 App」横幅与 Cookie 提示、
  把 `target="_blank"` 的链接改成当前窗口打开、关掉自动字号放大。
  命中不了选择器时最多是没生效，不影响页面。
- 登录态就是 WebView 自己的 Cookie，重启应用仍在；换账号用「清除站点数据」。

## 妖火网为什么也只能走浏览器

- 匿名访问：首页只剩标题摘要，任何 `wapindex.aspx?classid=*` 与 `bbs-*.html` 都返回
  「温馨提示 请先登录网站！」；
- 登录 `POST /waplogin.aspx` 强制人机验证（Cloudflare Turnstile / 阿里云 / EngageLab 三家
  轮换），不带验证码直接回「请完成人机验证后再提交」；
- 页面本身是 IIS + ASP.NET 服务端渲染，HTML 可解析，卡住的只有登录这一步。
  以后要做原生，只能「内置浏览器登录一次 → 取 Cookie → 原生抓 wap 页面」。

## 已知限制

- 内置浏览器里的站点**不做页面结构解析**：没有原生列表、没有离线缓存、没有
  「已读楼层」这类本地增强，这些能力仍只属于 Discuz 站点。
- 深色外观由站点自己的主题开关决定，应用只负责顶栏跟随系统主题。
- 「版块」「搜索」两个原生 tab 在浏览器模式下不出现——它们是 Discuz 专用入口。

## 代码位置

| 文件 | 作用 |
| --- | --- |
| `lib/core/sites.dart` | 站点模型（`SiteProfile`）、内置站点表、选择持久化（`SiteStore`） |
| `lib/ui/pages/site_web_page.dart` | 内置浏览器承载页（顶栏、快捷入口、注入脚本） |
| `lib/ui/pages/site_picker_page.dart` | 站点选择页、自定义站点输入 |
| `lib/ui/app_shell.dart` | 站点为 `web` 模式时整棵树换成浏览器页 |
| `lib/main.dart` | 首帧前读回站点选择，并把站点与主题两路通知合并监听 |

## 构建与安装

包名没变（`cc.binmt.mt_forum`），但签名换了：**覆盖安装会失败，必须先卸载官方版**
（本地数据、登录态会一起没）。改动只在 Dart 层，`android/` 没有动。

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

或者推到 GitHub，仓库自带的 `Build APK` workflow 会构建并把产物挂到 Releases。
