# Kelivo Plus 1.1.17+9015 Release Notes

发布日期：2026-07-29

本版本是基于 [Chevey339/kelivo](https://github.com/Chevey339/kelivo) 的二次开发公开版本，源代码版本号为 `1.1.17+9015`。本次发布重点补齐移动端推理强度滑块、共存安装包构建参数、9015 APK 发布说明，并保留此前整合的神经权能网关、Skills、内置 MCP、GitHub 写入工具和本地混合搜索能力。

## 下载

Release 资产包含 9015 Android 通用共存 APK：

```text
Kelivo_android_1.1.17+9015_reasoning-help-right-particles_coexist_fixedsign_universal.apk
```

SHA256：

```text
883FEA1DB7A2465569D7D56093A4A1D028DEB3C001DE73A5CEF51E6D4F775285
```

## 9015 重点变化

- 新增移动端推理强度滑块的共存构建支持。
- 9015 APK 使用独立 Android 包名 `com.psyche.kelivo.sliderpreview`。
- 启动器显示名称为 `Kelivo Slider`，可与原版 Kelivo 同时安装。
- 保留默认源码包名 `com.psyche.kelivo`；只有传入 Gradle 参数时才生成共存包。
- README 已更新为 9015 下载地址和共存安装说明。

## 已继承能力

- 神经权能网关：允许授权助手在对话中导入、编辑和撤销 App 配置。
- Skills 系统：支持创建、导入、触发词匹配和助手绑定。
- 内置 MCP 服务：Fetch、Files、Images、GitHub 等内置工具继续可用。
- GitHub 写入工具：支持仓库、文件、Issue、PR、Release、Actions、Secrets、Variables 等能力。
- Local Hybrid Search：无需 API Key，聚合多源本地搜索并进行过滤、去重和排序。
- Android 分享导入：支持文本和多类型文件进入对话，再由助手导入到目标配置。

## 安装与共存

- 9015 共存 APK 不会覆盖原版 Kelivo。
- 原版包名仍是 `com.psyche.kelivo`，9015 共存包名是 `com.psyche.kelivo.sliderpreview`。
- 共存包与原版 Kelivo 使用独立应用数据，不会直接读取原版私有数据。
- 如需迁移配置、聊天记录、助手、MCP 或模型设置，请通过备份/导入完成。

共存构建示例：

```powershell
flutter build apk --release `
  -PkelivoApplicationId=com.psyche.kelivo.sliderpreview `
  -PkelivoAppLabel="Kelivo Slider"
```

## 验证

9015 发布前已围绕移动端推理滑块、MCP、备份同步、模型兼容和聊天输入相关路径进行针对性验证。完整 `flutter analyze` 仍可能受到 vendored `dependencies/mcp_client/test` 上下文影响，建议继续使用项目说明中的 targeted tests 作为日常验证基线。
