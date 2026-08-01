# Android 安装与共存说明

## 当前 Release APK 类型

当前公开 Release 附带的 APK 是同包名版本：

```text
com.psyche.kelivo
```

这个包名与原版 [Chevey339/kelivo](https://github.com/Chevey339/kelivo) 相同。Android 以包名识别应用，因此它会把原版 Kelivo 和 Kelivo Plus 视为同一个应用。

## 不能做什么

- 不能直接覆盖安装原版 Kelivo：除非签名证书完全一致，否则 Android 会拒绝安装。
- 不能与原版 Kelivo 直接共存：同一个包名在同一台设备上只能安装一个。
- 不能通过改文件名实现共存：APK 文件名不影响 Android 应用身份，包名才是关键。

## 推荐安装方式

1. 打开原版 Kelivo，导出或备份需要保留的数据。
2. 卸载原版 Kelivo。
3. 从本仓库 GitHub Releases 下载 Kelivo Plus APK。
4. 安装 Kelivo Plus。
5. 在 Kelivo Plus 中重新导入数据或配置模型、助手、MCP、GitHub Token。

## 从旧二改版升级

如果已经安装过同签名的 Kelivo Plus 二改版，可以直接覆盖安装。覆盖安装需要同时满足：

- 包名相同。
- 签名相同。
- 新 APK 的 versionCode 不低于已安装版本。

如果提示“无法降级”，说明设备上已安装版本的 versionCode 更高，需要使用更高 versionCode 的 APK，或先备份数据后卸载再安装。

## 与原版共存的方法

要与原版 Kelivo 共存，必须构建独立包名版本。建议做法：

1. 修改 `android/app/build.gradle.kts` 中的 `applicationId`，例如：

```kotlin
applicationId = "com.psyche.kelivo.plus"
```

2. 可选：修改 `android/app/src/main/AndroidManifest.xml` 中的应用名称，让桌面显示为 `Kelivo Plus`。
3. 使用自己的 Android 签名重新构建 APK。
4. 安装后，系统会把它视为另一个应用。

注意：共存版与原版的数据目录不同，不能直接共享私有数据。需要通过原版的备份/导出功能迁移到共存版。

## 为什么 Release 不直接使用共存包名

当前 Release 优先保证旧 Kelivo Plus 二改版用户可以覆盖升级，所以保留 `com.psyche.kelivo` 包名。未来可以单独发布 `coexist` 变体，使用 `com.psyche.kelivo.plus` 之类的独立包名。
