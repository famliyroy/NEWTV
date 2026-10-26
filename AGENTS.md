# AGENTS.md

## 项目
MoonTVPlus 的原生 Flutter 客户端（Windows + Android）。后端是**已部署的线上 MoonTVPlus 实例**，只通过 HTTP API 调用，**不得修改后端任何代码**。

## 必读顺序
`docs/07-AI开发交接指南.md` → `docs/03-开发计划与任务分解.md` → `docs/02-客户端架构方案.md` → `docs/05-UI交互设计规格.md` → `docs/06-弹幕全自动加载方案.md` → `docs/01-逆向分析报告.md`

文档冲突时，**以 07 为准**。

## 铁律（违反即返工）
1. 代码/资源/注释中**不得出现真实域名、IP、密码**；示例统一用 `example.com`
2. 不改后端；不用 WebView 套壳；不更换播放内核（固定 `media_kit`）
3. 播放地址必须经 `/api/proxy-m3u8` 代理，禁止直连原始地址；`url` 参数必须 `Uri.encodeComponent`
4. 鉴权：持久化**整个 CookieJar**；401 只重放 1 次；并发 401 **单飞 refresh**
5. 弹幕：多源自动加载、**零点击**；不阻塞起播；失败不弹模态框；关闭开关后不发请求
6. `episode_matcher` / `danmaku_merger` / `title_cleaner` 三个纯函数模块**先写测试**，覆盖率 100%
7. 一个任务一个 commit，message 带任务 ID（如 `feat(player): T-3.2 播放页两段式控制层`）
8. 架构级歧义必须先问（给 2 个方案 + 推荐），不要自行发挥
9. 日志禁止打印 cookie / token / password / 完整视频 URL
10. keystore、`.env`、`key.properties` 永不入仓库

## 接口
只用 `docs/01-逆向分析报告.md` §13 列出的 12 个接口，路径只在 `lib/data/api/endpoints.dart` 出现一次。

## 常用命令
```bash
flutter analyze
flutter test --coverage
flutter build windows --release
flutter build apk --release --split-per-abi
```

## 完成定义
`flutter analyze` 0 error + 测试通过 + `docs/03` 中该任务验收标准逐条实测通过（贴证据）+ 无 TODO 遗留 + 已更新 CHANGELOG。
