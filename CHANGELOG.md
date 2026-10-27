# Changelog

本项目遵循语义化版本。

## [Unreleased]

## [0.1.4] - 2026-10-27

### Fixed

- **改完设置不生效，必须退回上级页面甚至重开 APP**：根因是全 APP 取设置都用了一次性快照——`appDependenciesProvider` 引用的对象永远不变，它内部 `SettingsController` 的通知无法触发重建，只有 `app.dart` 的主题正确 watch 了。现在：
  - `settingsProvider` / `sessionProvider` 收敛到 `providers.dart` 并以 `ChangeNotifierProvider<SettingsController>` 暴露，播放页、设置页、弹幕设置 sheet 全部改为 `ref.watch`，拖动滑块自身立即刷新。
  - `PlayerController` 改为持有 `SettingsController`（而非值快照），构建 `/api/proxy-m3u8` 时**每次现场读** `adblock` / `proxySegments` / `playbackToken`，播放中改去广告开关后点重试即按新值走。
  - 弹幕开关收敛为单一事实来源：播放页按钮、设置页开关、sheet 里的开关都写 `danmakuEnabled`，胶囊与 overlay 同步变化；从关到开时自动补一次加载。
- **沉浸态仍有 UI 残留**：`_ProgressBar` 此前收起时只是从 `bottom: 76` 移到 `12` 继续显示，现在与控制栏一起 `Opacity 0 + IgnorePointer` 淡出；弹幕状态胶囊改为瞬时提示（成功 3 秒、失败 5 秒自动消失，此前 `_status` 永不清空导致常驻右下角），并跟随控制栏显隐。

### Added

- **弹幕服务可切换**：设置页新增「弹幕服务」区块，可在 `MoonTVPlus 后端`（默认）与`自定义弹幕 API`之间单选，后者可填 base URL 并「测试连通」。新增 `DanmakuSource` 抽象，落地自建 LogVar 弹幕 API 实现（`/api/v2/search/anime`、`/api/v2/bangumi/{id}`、`/api/v2/comment?url=<完整地址>`），适配该服务 `p` 只有 4 段（时间,模式,颜色,池）的格式；请求串行化并保证间隔 ≥1.1s、429 指数退避重试；该源本身已是多源聚合，自动跳过客户端多源合并，且使用独立缓存键避免与后端弹幕串味。
- **详情页播放源常驻 + 搜索更多源**：即使只命中 1 个源也展示「源名 · N 集」与选中态；新增「搜索更多源」弹层，按标题聚合展示所有候选组，选中即把整组追加进源列表并切换。失效源（详情返回 0 集）在 chip 上标注「无选集」。
- **播放页换源**：控制栏新增换源按钮（失败页的「切换播放源」保留），换源后保留当前集号并对齐到新源的同一集，同时重新加载弹幕。
- **清晰度切换与测速**：起播后后台经 `/api/proxy-m3u8` 取 master playlist，解析 `#EXT-X-STREAM-INF` 变体（BANDWIDTH / RESOLUTION），对每个变体的首个分片发 `Range: bytes=0-262143` 请求实测速率并在菜单里显示（如 `1080P · 2.3 MB/s`）；选择后切到该变体的子 m3u8 并回到原进度，「自动」取测速最优；单码率只显示「自动（单一流）」，不报错。
- 设置页新增「沉浸模式保留迷你进度条」（默认关）。

## [0.1.3] - 2026-10-27

### Fixed

- **首页点「热门电影」「近期热门」进详情报「请求失败（400）」、共 0 集、无法播放**：这两个板块来自 `/api/douban/recommends` 与 `/api/tmdb/trending`，条目只有豆瓣/TMDB 的 id，没有可播放的 `source`，直接请求 `/api/detail` 必被后端拒绝。现在进入详情页时会先用标题走 `/api/search` 聚合搜索接源，取同名多源分组（年份最接近的排最前）再请求详情；搜索不到时明确提示「未在任何片源找到该片」，同时保留标题/海报/年份展示。
- **同名多源里部分源早已失效（详情返回 0 集）**：详情加载后若当前源没有选集，自动切到同组下一个源，不再停在「共 0 集 / 暂无可播放选集」；手动选源时不做自动跳转，尊重用户选择。
- **豆瓣 / TMDB 海报全部破图**：新增 `SmartImage` 统一出图，`*.doubanio.com`、`image.tmdb.org` 改写成服务端 `/api/image-proxy?url=`（带当前登录 Cookie，该接口实测未登录返回 401），代理失败自动回退直连原图，两者都失败才显示占位。番剧图床（`lain.bgm.tv`）保持直连以免浪费服务器带宽。
- **播放失败（`Failed to open https://.../index.m3u8`）**：
  - 直连候选的 UA 由 `NEWTV/0.1` 改为桌面浏览器 UA——部分片源站 WAF 会拒绝非浏览器标识，表现为连接被重置。
  - 勾选「允许自签名证书」时，同步对 libmpv 关闭 `tls-verify`（此前只对 dio 生效，自签名服务器走代理必然失败）。
  - 候选链从两级扩展为三级：**服务端取 m3u8 → 直连源站 → 全量代理分片**（`proxySegments=true`），最后一档用于本机到源站 CDN 完全不通的场景。
  - 打开前先用 dio 预检代理地址：服务端取流失败时直接跳过该候选，并把后端返回的 `error` 文案显示在失败页，便于区分「服务器取源失败」与「本机网络问题」。
- **错误文案过于笼统**：4xx/5xx 优先透传后端响应体里的 `error` / `message`（如「无效的API来源」），不再一律显示「请求失败（400）」。

### Added

- 播放失败页新增「切换播放源」，可直接在播放器内换源重试，无需退回详情页。


## [0.1.2] - 2026-10-27

### Fixed

- **发现页空白**：接入 `/api/douban/recommends`，提供「电影 / 剧集 / 热门」三个 Tab（热门走 `/api/tmdb/trending`），卡片展示评分角标、年份，点击可直接搜索该片。
- **新番页无数据**：接入 `/api/bangumi/schedule`（失败时自动回退 `/api/bangumi/calendar`），按周一至周日分组，显示更新日期、评分、总条目数；兼容 `{days:[{slots:[{items}]}]}` 与 `[{weekday,items}]` 两种返回结构。
- **选集区看不清片源与集数**：选集按钮改为「第 N 集 · 原标题」并自动去重（后端标题本身就是「第01集」时不再重复），片源按钮显示「源名 · 集数」；单片（短剧「全集」）直接使用源标题。
- **详情页闪烁**：头部模糊背景改用 `RepaintBoundary` 包裹并把路由淡入时长设为 0，翻页不再整屏闪。
- **播放页无法退出**：改用 `go_router` 的 `pop()`（`Navigator.maybePop` 在 ShellRoute 下会静默失败），并加幂等保护；退出时恢复竖屏与系统栏。
- **播放失败（核心）**：
  - 部分源站返回 **Brotli 压缩**的播放列表，`libmpv` 无法解压，直接报 `Failed to recognize file format`。现同时发送 `Accept-Encoding: identity`，并让 m3u8 优先经服务端 `/api/proxy-m3u8` 取回（服务端返回原始内容），分片仍直连以保证速度。
  - 新增**双链路自动回退**：代理失败自动切直连，直连失败自动切代理，全部失败才提示「播放失败」。
  - 播放中途的网络抖动（`tcp: ffurl_read` 等）不再被误判为整集失败，交给 mpv 自行重试。
- **首页卡片文字溢出**：`PosterCard` 高度改为按海报比例 + 实际文本行高动态计算，修复 `BOTTOM OVERFLOWED BY 6~7 PIXELS`；`GridView` 中的卡片改为自适应格子宽度，窄屏不再横向溢出。
- **详情接口 500 时体验差**：改为浅色轻提示「详情补全失败，当前显示搜索结果」，页面仍可用搜索结果正常播放。

### Changed

- 「服务端去广告切片」默认关闭：服务器与片源常处于不同网络，默认走直连更稳；需要过滤广告切片的用户可自行开启。
- 设置项文案补充说明代理失败会自动改回直连。


## [0.1.1] - 2026-10-27

### Fixed

- **登录页丢失用户名输入框**：`GET /api/server-config` 实际返回**顶层扁平字段**（`StorageType` / `LoginRequireTurnstile` / `TurnstileSiteKey`），原实现只读嵌套的 `data['SiteConfig'][...]`，导致 `storageType` 恒为空字符串，登录页据此把用户名输入框隐藏。现同时兼容顶层与嵌套两种结构，且登录页默认显示用户名，仅在明确识别为 `localstorage`（仅密码）时才隐藏；进入登录页时还会静默重新探测一次并回写缓存，升级后无需重新添加服务器。
- 登录失败时优先展示服务端返回的具体原因（如「用户名或密码错误」「用户被封禁」「请完成人机验证」「人机验证失败，请重试」），不再一律提示「登录失败」。

### Added

- **Cloudflare Turnstile 兼容**：探测阶段记录 `LoginRequireTurnstile`，登录页据此展示提示；支持可选的 `turnstileToken` 提交；并提供「Cookie 授权登录」通道——粘贴浏览器登录后的 `auth` Cookie 直接写入加密 CookieJar，再用 `/api/playrecords` 校验会话，可在不关闭 Turnstile 的情况下登录。
- CI 新增 `Publish GitHub Release` 作业：推送 `v*` 标签时，自动下载 `newtv-android` / `newtv-windows` 产物并创建 GitHub Release，挂载 `app-release.apk`、`newtv-windows-x64.zip` 及两者的 `.sha256`；正文自动截取本文件对应版本段落。

### Changed

- Android SHA256 校验文件改为仅记录文件名（`app-release.apk`），可直接用 `shasum -a 256 -c` 校验。

## [0.1.0] - 2026-10-26

### Added

- 初始化 NEWTV Flutter 工程（`moontv_client/`），目标平台为 Windows、Android 手机和 Android TV（含 `LEANBACK_LAUNCHER` 与 DPAD 焦点支持）。
- 确立 `dev.moontv.client` Android `applicationId`。
- 实现弹幕标题清洗（`title_cleaner`）、集数匹配（`episode_matcher`，P0–P4 优先级，防日期误判）、多源合并去重（`danmaku_merger`）纯函数三件套及完整单元测试。
- 实现服务器探测引导页、HMAC CookieJar 安全持久化、401 单飞刷新拦截器（`auth_interceptor`）。
- 实现首页（继续观看/今日更新/热门推荐）、发现页、搜索页（300ms 防抖 + 同名多源折叠）、详情页（Hero 过渡 + 选源保集号 + 收藏同步）、追番周表（周一至周日筛选）、我的页面（收藏/历史同步删除）与设置页（服务器/播放/弹幕/外观/开源许可五组配置）。
- 实现基于 `media_kit` 的两段式控制层播放器（`/api/proxy-m3u8` 代理、每 30s 播放进度云端同步、断点续播、自动连播下一集、倍速/比例切换）与二分查找时间窗 `CustomPainter` 弹幕渲染层。
- 配置 GitHub Actions 多平台持续集成流水线（`.github/workflows/ci.yml`），包含 `flutter analyze`、76 项单测、S1/S3/S4 隐私与许可证门禁、Android APK 与 Windows EXE 自动打包及 SHA256 校验。

### Verification

- `dart analyze`：0 issue；`flutter test`：76/76 全部通过。
- S1/S3/S4 敏感信息与许可证门禁扫描通过。
- Android APK 本机构建通过（`app-debug.apk`）。
