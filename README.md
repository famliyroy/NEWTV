# NEWTV — MoonTVPlus 原生多端客户端（Windows / Android / Android TV）

为已在服务器运行的 [mtvpls/MoonTVPlus](https://github.com/mtvpls/MoonTVPlus) 打造的**原生 Flutter 客户端**（位于 `moontv_client/`）：界面与交互参考 [NipaPlay-Reload](https://github.com/AimesSoft/NipaPlay-Reload) 的暗色玻璃拟态与两段式播放控制设计语言，支持**弹幕多源全自动聚合加载（零点击）**、**播放进度与收藏跨端实时同步**，后端零改动。

> **安全声明**：本仓库不包含任何私人服务器域名、IP、密码或影视源，首次启动由用户自行填写自建服务器地址。

---

## 核心特性

- **多平台同源构建**：一套 Flutter 3 + `media_kit`（libmpv）代码同时构建 **Windows EXE**、**Android 手机 APK** 与 **Android TV（Leanback + DPAD 遥控焦点导航）**。
- **全自动多源弹幕聚合**：
  - 标题清洗（剔除季数/语种/分辨率标签）→ 多源搜索 → P0–P4 优先级剧集匹配（严禁盲取第一集）→ 最大 6 路并发拉取 → `0.1s 时间桶 + 归一化文本` 合并去重。
  - `CustomPainter` 二分查找时间窗三轨渲染（滚动 / 顶部 / 底部），与视频起播完全并行，零弹窗静默降级，本地缓存 7 天 TTL。
- **NipaPlay 风格玻璃拟态 UI 与两段式播放器**：
  - `GlassCard`（`BackdropFilter` + 半透明层 + 1px 高光描边），支持深浅色主题与减弱动效模式。
  - 播放页 3 秒无操作自动收起至底部极简进度细条；支持双击左右 ±10s、长按 2.0x 临时倍速、0.5x–3.0x 常驻倍速、画面比例切换、自动连播下一集及桌面端快捷键（`Space` / `←` / `→` / `F` / `D` / `N` / `Esc`）。
- **与 MoonTVPlus 后端深度同步**：
  - 完整持久化 HMAC 签名 CookieJar，遇 `401` 单飞调用 `/api/auth/refresh` 自动续期并重放原请求一次。
  - 播放流统一走免鉴权 `/api/proxy-m3u8`（支持去广告切片、TS 分片代理与可选播放令牌）。
  - 观看历史（每 30s 及切集/退出自动上报 `/api/playrecords`、断点续播）与收藏夹（`/api/favorites`）跨设备实时同步。

---

## 下载安装包

正式构建产物发布在 **[Releases](https://github.com/famliyroy/NEWTV/releases)** 页面，每个版本包含 4 个文件：

| 文件 | 说明 |
| --- | --- |
| `app-release.apk` | Android 手机 / Android TV 通用安装包（universal，含 arm64-v8a / armeabi-v7a / x86_64） |
| `app-release.apk.sha256` | APK 校验值 |
| `newtv-windows-x64.zip` | Windows x64 免安装压缩包，解压后运行 `newtv.exe` |
| `newtv-windows-x64.zip.sha256` | Windows 包校验值 |

校验方式：

```bash
# macOS / Linux
shasum -a 256 -c app-release.apk.sha256
# Windows PowerShell
Get-FileHash newtv-windows-x64.zip -Algorithm SHA256
```

> **为何有时在 Releases 看不到文件**：分支推送（`main` / `develop` / `release/*`）只会把产物存进 Actions 运行的 Artifacts（需登录、保留 90 天）；**只有推送 `v*` 标签才会创建 Release**。发布新版本请执行：
>
> ```bash
> git tag -a v0.1.1 -m "NEWTV v0.1.1" && git push origin tag v0.1.1
> ```

---

## 快速开始与构建说明

### 1. 本地开发与测试

```bash
cd moontv_client
flutter pub get
dart analyze
flutter test
```

### 2. 打包构建

- **Android APK**：
  ```bash
  cd moontv_client
  flutter build apk --release
  ```
- **Windows EXE**：
  ```bash
  cd moontv_client
  flutter config --enable-windows-desktop
  flutter build windows --release
  ```
- **GitHub Actions 自动构建**：推送至 `main`、`develop`、`release/*` 分支或 `v*` 标签时，`.github/workflows/ci.yml` 自动执行静态分析、76 项单元测试、安全合规门禁扫描，并产出 `newtv-android`（APK + SHA256）与 `newtv-windows`（ZIP + SHA256）构建产物。
  - 分支推送 → 产物进入该次 Actions 运行的 **Artifacts**；
  - `v*` 标签推送 → 额外触发 `Publish GitHub Release` 作业，把 APK / Windows ZIP 及其 SHA256 **发布到 Releases 页面**（正文自动截取 `CHANGELOG.md` 对应版本段落）。

---

## 它是什么，不是什么

| 是 | 不是 |
| --- | --- |
| 原生 Flutter App（Windows EXE + Android APK，同套代码） | 不是 WebView 套壳 |
| 连接你**已有**的 MoonTVPlus 服务端（纯 API 客户端） | 不含后端、不内置任何影视源 |
| 界面与交互参考 NipaPlay-Reload（MIT） | 不是它的换皮或分支 |
| 播放记录 / 收藏全在服务端，多端天然同步 | 不做本地片库、不做视频下载 |
| 包体约 32 MB（Windows ZIP）/ 约 95 MB（Android universal APK，含全 ABI） | 不是 200 MB 的"全家桶" |

**为什么必须是原生**：NipaPlay 风格界面和"弹幕全自动加载"都是**前端行为**。WebView 壳里前端跑在服务器上，不改后端就只能放弃这两个需求。

---

## 文档导航

> **接手的 AI / 开发者请按此顺序读**：07 → 03 → 02 → 05 → 06 → 01

| 文档 | 内容 | 读者 |
| --- | --- | --- |
| [07-AI开发交接指南](docs/07-AI开发交接指南.md) | **执行契约**：开工前确认项、绝对禁止、任务流程、交接自检 | **接手第一天必读** |
| [03-开发计划与任务分解](docs/03-开发计划与任务分解.md) | 6 个里程碑、38 条 WBS（含依赖与验收）、关键路径、CI 矩阵、验收清单 | 项目管理 / 执行者 |
| [02-客户端架构方案](docs/02-客户端架构方案.md) | Flutter 选型论证、分层与目录、鉴权令牌链路、播放链路、构建发布、性能预算 | 开发者 |
| [05-UI交互设计规格](docs/05-UI交互设计规格.md) | 设计 token、9 个页面规格、播放器两段式控制层、动效、双端适配矩阵 | UI / 前端 |
| [06-弹幕全自动加载方案](docs/06-弹幕全自动加载方案.md) | 多源发现、集数匹配算法、并发拉取、合并去重、性能上限、降级策略 | 核心功能开发者 |
| [01-逆向分析报告](docs/01-逆向分析报告.md) | 运行时拓扑、模块地图、鉴权机制、**§13 完整接口契约** | 技术决策 / 对接 |
| [04-风险登记与合规审查](docs/04-风险登记与合规审查.md) | 16 条技术/合规/执行风险、许可证冲突、开工检查表 | 项目负责人（**开工前必读**） |
| [archive/](docs/archive/) | 已作废方案（内嵌引擎、WebView 薄壳），保留以说明为何否决 | 存档 |

---

## 一页纸结论

**后端（已实测核验）**：Docker 容器 `moontv-core` → nginx 反代 → **HTTPS + Let's Encrypt**（自动续期）→ kvrocks 存储。匿名访问 `307 → /login`，登录保护已开。**251 个 API 路由**，是全栈单体，但对外就是一套 HTTP 接口。

**客户端**
- **技术栈**：Flutter 3 + `media_kit`（libmpv）+ Riverpod + drift；一套代码出 Win/Android
- **鉴权**：Cookie `auth`（HMAC 签名 + access/refresh 双令牌），客户端需完整复刻浏览器行为
- **播放**：必须经 `/api/proxy-m3u8`（**免鉴权**，这是本项目最大的架构便利）
- **弹幕**：客户端自己聚合 —— 后端代理只给单源且未开 `withRelated`，多源合并是我们要补的那一层

**规模**：38 条任务 / 7 个工作包 / **48.5 人日**。单人约 10 周；双人约 5.5 周；**最小可用版 18 人日（约 3.5 周）**。

---

## ⚠️ 开工前必须先处理的三件事

**1. 弹幕源必须真的可用**
内置公共弹幕源 `mtvpls-danmu.netlify.app` 实测返回 **503 已失效**。若服务端 `SiteConfig.DanmakuApiBase` 未指向可用服务，弹幕功能**全部无法验收**——"全自动加载"再漂亮也是加载空气。

**2. 客户端默认地址不能写进公开仓库**
写死 = 你的私人站点地址随源码公开，可能被爬、被举报、被打；即便源码脱敏，Release 包 `strings` 一下照样能掏出域名。
处理：公开版**不含任何地址**，首次启动要求填写；文档与截图统一 `example.com`；CI 加硬编码扫描（`03` 第 5 节 S1）。

**3. 工期不能按薄壳估**
薄壳 20 人日、原生 48.5 人日，差在"没有前端"。而主人要的两个需求恰好都是前端。按 20 人日排期会直接崩盘。

---

## 里程碑

| 里程碑 | 版本 | 累计人日 | 退出标准 |
| --- | --- | ---: | --- |
| M0 契约冻结与骨架 | `v0.1.0` | 2 | 可构建、接口 fixtures 就位、许可文件齐全 |
| M1 最小可用版 | `v0.2.0` | **18** | 填地址→登录→搜索→详情→**能播放** |
| M2 完整业务页面 | `v0.4.0` | 30.5 | 首页/追番/我的/设置 全部可用，空态齐全 |
| M3 弹幕全自动 | `v0.6.0` | 38.5 | 弹幕 A1–A10 验收全绿，零点击出弹幕 |
| M4 双端打磨 | `v0.9.0` | 44.5 | 双端清单全绿、性能预算达标 |
| M5 发布 | `v1.0.0` | 48.5 | Release 可下载、文档齐全 |

---

## 与上游的关系

| 项 | 说明 |
| --- | --- |
| 是否改上游代码 | **否**，零 patch，只调其 HTTP API |
| 上游升级 | 客户端依赖面收敛在 `01` §13 的 12 个接口；变了在 `server-config` 探测处提示 |
| 许可证（上游） | `LICENSE` 正文为 **CC BY-NC-SA 4.0**（README 标 MIT，冲突以正文为准）。**NC 意味着本项目不得商用** |
| 许可证（参考项目） | NipaPlay-Reload 为 **MIT**，可读码借鉴，须保留版权声明并写入 `CREDITS.md` |

上游：[mtvpls/MoonTVPlus](https://github.com/mtvpls/MoonTVPlus) © 2025 MoonTV & Contributors
参考：[AimesSoft/NipaPlay-Reload](https://github.com/AimesSoft/NipaPlay-Reload)（MIT）

---

## 下一步

1. 过 [04](docs/04-风险登记与合规审查.md) 的「开工前检查表」（30 分钟）。
2. 按 [07](docs/07-AI开发交接指南.md) 第 2 节确认 6 项信息。
3. 进 M0：建骨架、抓真实接口响应存 fixtures、配许可文件。
4. 然后 M1：**先让它能看片**（18 人日）——这是最关键的一次验证。

---

## 免责声明

本项目仅提供客户端软件，不内置、不托管、不分发任何音视频内容，也不包含任何数据源配置。使用者需自行部署服务端并自行承担相应责任。本项目不得用于商业用途（受上游 CC BY-NC-SA 4.0 的 NC 条款约束）。
