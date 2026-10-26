# Changelog

本项目遵循语义化版本。

## [Unreleased]

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
