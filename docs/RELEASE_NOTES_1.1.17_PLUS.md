# Kelivo Plus 1.1.17+4069 Release Notes

发布日期：2026-07-26

本版本是基于 [Chevey339/kelivo](https://github.com/Chevey339/kelivo) 的二次开发公开版本，重点整合 App Control Agent、Skills、内置 MCP、GitHub 写入工具、本地混合搜索和 Android 移动端导入增强。

## 下载

Release 资产包含最新版 Android arm64 APK：

```text
Kelivo_android_1.1.17+4069_github-tools-parameter-hardening_fixedsign_arm64-v8a.apk
```

SHA256：

```text
091DD976A05AB950BF8B64391FC592EF289356A3797DB1A88574AB8B4118C0AD
```

## 重要变更

- 新增 App Control Agent：允许授权助手在对话中导入、编辑和撤销 App 配置。
- 新增助手级高权限开关：默认关闭，用户可按助手授予配置控制能力。
- 新增 Skills 系统：支持创建、导入、触发词匹配和助手绑定。
- 新增内置 MCP 服务：Files、Images、GitHub，并保留 Fetch。
- 升级 GitHub MCP：支持仓库、文件、Issue、PR、Release、Actions、Secrets、Variables 等写入和管理能力。
- 优化 GitHub 工具封装：按业务分组，中文工具说明，参数按 GitHub API 规则收敛。
- 新增 Local Hybrid Search：无需 API Key，聚合多个本地搜索源并进行过滤、去重、排序。
- 增强 Android 分享导入：支持文本和多类型文件进入对话，再由助手导入到目标配置。

## GitHub 工具修复

- 空仓库创建分支前自动初始化 README。
- `GITHUB_` 变量名前缀提前报错并提示替代前缀。
- 写入后不使用 code search 作为强一致验证。
- PR update 使用最小 payload，避免无关字段导致 422。
- PR 行内评论与回复评论拆分为不同路径。
- 支持多行评论和 file-level comment 常用字段。

## 升级提示

- 本 Release APK 的包名是 `com.psyche.kelivo`，与原版 Kelivo 相同。
- 不能直接覆盖安装原版 Kelivo：原版和二改版通常签名不同，Android 会报签名冲突。
- 不能与原版 Kelivo 直接共存：同一包名在同一设备上只能安装一个应用。
- 推荐先备份/导出原版数据，卸载原版，再安装 Kelivo Plus。
- 如需共存，请自行构建独立包名版本，例如把 Android `applicationId` 改为 `com.psyche.kelivo.plus`，并用自己的签名打包；共存版拥有独立应用数据，需要通过备份/导入迁移。
- 覆盖安装旧 Kelivo Plus 二改版要求 APK 签名与已安装版本一致。
- 如果 Android 提示“无法降级”，请确认当前已安装版本号是否高于 `1.1.17+4069`。
- GitHub Token 不会随应用内置，需要在 MCP 编辑页自行配置。
- App Control Agent 是高权限能力，仅建议对可信助手开启。

## 验证

已针对本版本相关模块运行重点测试：

```powershell
flutter analyze lib\core\services\mcp\kelivo_github\github_api_client.dart lib\core\services\mcp\kelivo_github\kelivo_github_server.dart test\kelivo_github_mcp_server_test.dart lib\core\providers\mcp_provider.dart
flutter test test\core\providers\mcp_provider_builtin_test.dart test\kelivo_github_mcp_server_test.dart
```

历史整合测试还覆盖 Skills、Files、Images、本地混合搜索和 App Control 相关模块。完整 `flutter analyze` 可能受 vendored `dependencies/mcp_client/test` 上下文影响，需要单独处理 analyzer exclude 后再执行。
