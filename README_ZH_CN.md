# Kelivo Plus

Kelivo Plus 是基于 [Chevey339/kelivo](https://github.com/Chevey339/kelivo) 的二次开发版本。原版 Kelivo 是一个跨平台 Flutter LLM 聊天客户端，本版本在保留原有模型接入、聊天、多模态、MCP、搜索和桌面/移动端体验的基础上，重点增强了移动端 AI 自主配置、内置工具、技能系统、本地混合搜索和 GitHub 写入型 MCP 工具。

> 二次开发声明：本仓库不是原作者官方仓库，代码基于原项目进行扩展与改造。原项目版权、协议与鸣谢请见原仓库和本仓库保留的 `LICENSE`。本项目继续遵循 AGPL-3.0 协议开源。

## 与原版的主要差异

| 模块 | 原版 Kelivo | Kelivo Plus 二改版 |
| --- | --- | --- |
| 助手配置 | 主要依靠用户手动进入设置页编辑 | 新增神经权能网关，允许获得授权的助手在对话中执行配置导入、修改与撤销 |
| 助手权限 | 普通助手设置 | 新增“允许该助手启用神经权能网关”的权限开关，默认关闭 |
| 技能系统 | 无独立 Skills 工作流 | 新增技能模型、导入器、技能页、助手技能绑定和触发注入 |
| MCP 工具 | 原有 MCP 接入与内置 Fetch | 新增内置 Files、Images、GitHub 等 MCP 服务，并优化工具折叠与中文说明 |
| GitHub 工具 | 偏只读/基础能力 | 新增分组式写入工具，覆盖仓库、分支、文件、Issue、PR、Release、Actions、Secrets、Variables 等能力 |
| 搜索 | 多 API 搜索服务 | 新增本地混合搜索，聚合 Bing Local、DuckDuckGo、百度、搜狗、360，带过滤、去重和排序 |
| 移动端导入 | 手动导入为主 | 支持对话中从文本、上一条生成内容、分享文件等来源导入到目标配置 |
| 工具体验 | 工具列表较分散 | 工具可见介绍中文化，部分工具分组封装，降低上下文噪声 |

## 核心功能

### 神经权能网关

- 在助手设置中开启“允许该助手启用神经权能网关”后，助手可以通过对话执行授权范围内的配置操作。
- 支持把用户提供的指令、粘贴内容、文件内容、或“刚刚生成的内容”导入到指定位置。
- 支持目标包括当前助手系统提示词、记忆、技能、指令注入、世界书、MCP 绑定、本地工具、快捷短语、搜索设置等。
- 补齐删除、更新、列表/详情、世界书 entry 细粒度编辑、快捷短语排序、技能版本快照/回滚、批量导入导出和权限审计能力。
- 支持执行结果回显与撤销，降低误操作风险。
- 权限默认关闭，适合只给可信助手开启。

示例：

```text
把上面生成的代码审查规范导入为一个技能，绑定到当前助手，并设置触发词：review、代码审查。
```

```text
根据我发的这份设定文档，创建一个世界书，关键词用角色名和地点名。
```

### Skills 技能系统

- 支持创建、编辑、删除、导入技能。
- 支持 Markdown、JSON、YAML、DOCX、ZIP 等格式导入。
- 技能可绑定到指定助手，也可以通过触发词自动注入。
- 适合沉淀可复用工作流，例如代码审查、写作润色、商业分析、翻译风格、角色设定等。

### 内置 MCP 工具

- `@kelivo/fetch`：网页抓取和内容提取。
- `@kelivo/files`：本地文件读取、写入、目录浏览等文件能力。
- `@kelivo/images`：图片理解、图片任务辅助能力。
- `@kelivo/github`：GitHub 仓库、文件、Issue、PR、Release、Actions、Secrets、Variables 等能力。
- 内置 MCP 运行在 App 内部，不需要用户额外启动 Node/Python 服务。

### GitHub 写入工具

GitHub 工具按使用场景分组封装，不再把每个 API 端点都暴露成一个独立工具：

- 仓库管理：创建/查看/更新/删除仓库，管理分支、标签、提交、目录和文件。
- Issue 管理：创建、更新、关闭、评论、标签、指派等。
- PR 管理：创建、更新、合并、关闭、审查、行内评论、回复评论等。
- Release 管理：创建、编辑、发布、删除 release 和资源。
- Actions 管理：读取 workflow/run/job/log，触发、取消、重跑工作流。
- Secrets / Variables：仓库和环境级变量、密钥管理。

工具层已加入 GitHub API 规则收敛：空仓库建分支自动初始化、禁止 `GITHUB_` 变量名前缀、写入后使用强一致接口验证、PR 更新最小 payload、行内评论和回复评论分路径处理。

### 本地混合搜索

- 新增 Local Hybrid Search，无需 API Key。
- 聚合 Bing Local、DuckDuckGo、百度、搜狗、360。
- 中文查询会自动利用中文搜索源，英文/通用查询优先使用更稳定的本地源。
- 对搜索结果进行广告过滤、坏站过滤、URL 清洗、去重和权重排序。

## 使用说明

### 安装 APK

下载地址：

- 最新 Release 页面：[Kelivo Plus 1.1.17+4073](https://github.com/MuMu-0604/kelivo/releases/tag/v1.1.17-plus.4073)
- Android 通用 APK 直链：[Kelivo_android_1.1.17+4073_gateway-report-fixes_fixedsign_universal.apk](https://github.com/MuMu-0604/kelivo/releases/download/v1.1.17-plus.4073/Kelivo_android_1.1.17%2B4073_gateway-report-fixes_fixedsign_universal.apk)

本公开 APK 的 Android 包名仍为 `com.psyche.kelivo`，与原版 Kelivo 相同，因此需要注意：

- 不能直接覆盖安装原版 Kelivo：原版和本二改版通常使用不同签名，Android 会拒绝安装。
- 不能与原版 Kelivo 直接共存：同一台设备上同一个包名只能安装一个应用。
- 可以覆盖安装旧的 Kelivo Plus 二改版：前提是旧二改版使用同一签名，并且当前版本号不低于已安装版本。

推荐安装方式：

1. 如需保留原版数据，先在原版 Kelivo 内完成备份或导出。
2. 卸载原版 Kelivo。
3. 安装 Release 中的 Kelivo Plus APK。
4. 重新导入配置、聊天记录或手动完成必要设置。

如需与原版共存，需要构建独立包名版本：

1. 将 Android `applicationId` 改为例如 `com.psyche.kelivo.plus`。
2. 建议同步修改应用名称为 `Kelivo Plus`，避免桌面图标混淆。
3. 使用自己的签名重新构建 APK。
4. 该共存版会拥有独立应用数据，不能直接读取原版 Kelivo 的私有数据；需要通过备份/导入迁移。

当前 Release 附带的是同包名升级包，不是共存包。

### 配置模型

1. 打开 Kelivo Plus。
2. 进入模型或服务商设置。
3. 添加 OpenAI、Gemini、Anthropic 或其他兼容服务商。
4. 回到聊天页选择模型并开始对话。

### 开启神经权能网关

1. 进入助手设置。
2. 找到权限开关“允许该助手启用神经权能网关”。
3. 仅对可信助手开启。
4. 在对话中直接提出配置需求，例如“把这段内容导入为当前助手的系统提示词”。
5. 执行前根据提示确认，执行后可撤销最近一次变更。

### 使用 Skills

1. 进入 Skills 页面。
2. 新建技能，或导入 Markdown/JSON/YAML/DOCX/ZIP 技能文件。
3. 在助手设置的 Skills 标签页中绑定技能。
4. 聊天时也可以通过触发词自动启用相关技能。

### 配置 GitHub Token

1. 进入 MCP 页面。
2. 编辑内置 GitHub MCP 服务。
3. 在 GitHub Token 输入框填入 token。
4. 根据需要授予 `repo`、`workflow` 等 scope。
5. 回到聊天中调用 GitHub 工具。

建议使用最小权限 token，并只给可信助手开放写入型 GitHub 操作。

### 使用本地混合搜索

1. 进入搜索服务设置。
2. 启用 Local Hybrid Search。
3. 无需配置 API Key。
4. 在聊天中启用搜索后，助手会使用本地混合搜索返回结果。

## 从源码构建

环境建议：

- Flutter 3.44.1 或更高版本
- Dart 3.12.1 或更高版本
- Android SDK / NDK，Android 构建建议使用 arm64-v8a release 目标

常用命令：

```powershell
flutter pub get
flutter test test/core/providers/mcp_provider_builtin_test.dart test/kelivo_github_mcp_server_test.dart
flutter build apk --release --target-platform android-arm64
```

本地签名文件不包含在仓库中。需要自行配置 `android/key.properties` 或使用自己的 Android 签名方案。

## 安全说明

- 神经权能网关是高权限能力，默认关闭，建议只给可信助手开启；高风险覆盖、删除和批量导入操作会走确认与可撤销流程。
- GitHub 写入工具会修改远程仓库，请使用最小权限 token。
- Secrets、Token、Keystore、`android/key.properties`、构建缓存和 APK 产物不应提交到仓库。
- 本项目保留 AGPL-3.0 协议要求，分发修改版时请同步提供对应源码。

## 文档

- [二改功能说明](docs/KELIVO_PLUS_CHANGES_ZH.md)
- [Android 安装与共存说明](docs/ANDROID_INSTALLATION_ZH.md)
- [Release 说明](docs/RELEASE_NOTES_1.1.17_PLUS.md)
- [搜索升级记录](docs/KELIVO_SEARCH_UPGRADE_NOTES.md)

## 致谢

- 原项目：[Chevey339/kelivo](https://github.com/Chevey339/kelivo)
- UI 灵感来源：[RikkaHub](https://github.com/re-ovo/rikkahub)
- 感谢原作者和社区贡献者提供的基础工程。

## License

本项目基于 AGPL-3.0 协议开源，详见 [LICENSE](LICENSE)。
