# Changelog

本项目遵循语义化版本。

## [0.1.0] - 2026-10-26

### Added

- 初始化 NEWTV Flutter 工程，目标平台为 Windows、Android 手机和 Android TV。
- 确立 `dev.moontv.client` Android applicationId 与项目内 Flutter SDK 开发方式。
- 新增弹幕标题清洗、集数匹配、合并去重的纯函数及测试。
- 新增服务器配置、会话、网络、内容、播放器与弹幕模块目录。
- 新增第三方许可声明、持续集成与安全扫描基础配置。

### Verification

- `dart analyze`：0 issue；`flutter test`：76/76 通过。
- Android debug APK 本机构建通过（`app-debug.apk`，四 ABI 含调试符号约 198 MB；release 分包后单 ABI 预计 40–60 MB）。
- 待办：真实服务器账号联调（登录/搜索/播放/弹幕全链路）、Windows 构建（本机为 macOS，走 CI 或 Windows 机器）、release 签名与电视端真机验证。当前版本不是正式发布版。
