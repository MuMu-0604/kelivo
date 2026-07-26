# Kelivo Plus

[简体中文](README_ZH_CN.md) | English

Kelivo Plus is a modified open-source build based on [Chevey339/kelivo](https://github.com/Chevey339/kelivo). The original Kelivo is a cross-platform Flutter LLM chat client. This fork keeps the original chat, model provider, multimodal, MCP, search, and mobile/desktop foundations, then adds stronger mobile agent control, built-in tools, Skills, local hybrid search, and writable GitHub MCP tooling.

> Fork notice: this repository is not the official upstream repository. It is a secondary development build based on the original Kelivo project. Original copyright, acknowledgements, and license terms are preserved. This project remains licensed under AGPL-3.0.

## What Changed From Upstream

| Area | Upstream Kelivo | Kelivo Plus |
| --- | --- | --- |
| Assistant configuration | Mostly manual settings pages | 神经权能网关 can import and edit configuration from chat after explicit assistant authorization |
| Assistant permissions | Standard assistant settings | Adds an opt-in 神经权能网关 permission switch for app configuration control |
| Skills | No standalone reusable Skills workflow | Adds Skill model, importer, Skills page, assistant binding, and trigger-based injection |
| Built-in MCP | MCP integration with built-in Fetch | Adds built-in Files, Images, GitHub, and in-memory MCP services |
| GitHub tools | Read-oriented or basic tooling | Adds grouped write-capable tools for repos, files, issues, PRs, releases, actions, secrets, and variables |
| Search | Multiple API-backed providers | Adds API-key-free local hybrid search using Bing Local, DuckDuckGo, Baidu, Sogou, and 360 with filtering/ranking |
| Mobile import flow | Mostly manual import | Supports chat-driven import from text, previous generated content, shared files, and user instructions |
| Tool UX | Tool list can be noisy | Adds Chinese visible tool descriptions and grouped tool surfaces |

## Highlights

### 神经权能网关

- Enable per assistant through the “Allow this assistant to use 神经权能网关” switch.
- Import user-provided instructions, pasted text, shared files, or newly generated content into app configuration targets.
- Supported targets include assistant system prompts, memory, Skills, instruction injection, world books, MCP bindings, local tools, quick phrases, and search settings.
- Adds delete/update/list/detail operations, world-book entry editing, quick-phrase reorder, Skill version snapshots/rollback, batch import/export, and an audit log.
- Recent changes can be undone.
- Disabled by default and intended only for trusted assistants.

Example prompts:

```text
Import the content you just generated as a Skill, bind it to the current assistant, and use review/code-review as trigger keywords.
```

```text
Create a world book from this setting document and use character and location names as keywords.
```

### Skills

- Create, edit, delete, and import reusable Skills.
- Import Markdown, JSON, YAML, DOCX, and ZIP-based skill files.
- Bind Skills to assistants or activate them with trigger keywords.

### Built-In MCP Tools

- `@kelivo/fetch`: fetch and extract web content.
- `@kelivo/files`: local file read/write and directory operations.
- `@kelivo/images`: image-oriented helper tools.
- `@kelivo/github`: GitHub repository, file, issue, PR, release, Actions, secrets, and variables operations.

### GitHub Write Tools

The GitHub MCP server exposes grouped tools instead of one tool per API endpoint:

- Repository and file operations.
- Branch, tag, commit, directory, and file management.
- Issue and pull request workflows.
- Pull request merge and review comments, including inline and file-level comments.
- Release management.
- GitHub Actions workflow/run/job/log operations.
- Repository/environment secrets and variables.

The wrapper layer also follows GitHub API constraints more strictly: empty repositories are initialized before branch creation, reserved `GITHUB_` variable names are rejected early, fresh writes are verified with strong read APIs instead of code search, PR updates use minimal payloads, and review-comment creation is separated from reply-comment payloads.

### Local Hybrid Search

- API-key-free local search mode.
- Aggregates Bing Local, DuckDuckGo, Baidu, Sogou, and 360.
- Isolates provider failures, deduplicates URLs, removes low-value results, and ranks by provider/source quality.

## Usage

### Install Android APK

Download links:

- Latest Release page: [Kelivo Plus 1.1.17+4073](https://github.com/MuMu-0604/kelivo/releases/tag/v1.1.17-plus.4073)
- Direct Android universal APK: [Kelivo_android_1.1.17+4073_gateway-report-fixes_fixedsign_universal.apk](https://github.com/MuMu-0604/kelivo/releases/download/v1.1.17-plus.4073/Kelivo_android_1.1.17%2B4073_gateway-report-fixes_fixedsign_universal.apk)

The public APK keeps the Android package name `com.psyche.kelivo`, the same as upstream Kelivo, so Android treats it as the same app:

- It cannot be installed over the official upstream Kelivo app unless the signing certificate matches, which it normally does not.
- It cannot coexist with upstream Kelivo because Android only allows one installed app per package name.
- It can update an older Kelivo Plus build only when the signing certificate is the same and the version code is not lower.

Recommended installation path:

1. Back up or export data from upstream Kelivo if needed.
2. Uninstall upstream Kelivo.
3. Install the Kelivo Plus APK from Releases.
4. Import backups or reconfigure providers, assistants, MCP, and GitHub Token.

To coexist with upstream Kelivo, build a separate package-name variant:

1. Change Android `applicationId`, for example to `com.psyche.kelivo.plus`.
2. Optionally change the app label to `Kelivo Plus` to avoid launcher confusion.
3. Sign the APK with your own key.
4. Treat it as a separate app with separate app data; migrate data through backup/import rather than direct private-data sharing.

The current Release APK is a same-package build, not a coexistence build.

### Configure Models

1. Open Kelivo Plus.
2. Add a model provider such as OpenAI, Gemini, Anthropic, or another compatible endpoint.
3. Select the model in chat and start using it.

### Enable 神经权能网关

1. Open an assistant settings page.
2. Enable “Allow this assistant to use 神经权能网关”.
3. Ask the assistant to import or edit a supported configuration target from chat.
4. Review the generated action and undo recent changes when needed.

### Configure GitHub Token

1. Open the MCP page.
2. Edit the built-in GitHub MCP server.
3. Paste a GitHub token into the GitHub Token field.
4. Grant only the scopes you need, commonly `repo` and `workflow` for write workflows.

### Use Local Hybrid Search

1. Open Search service settings.
2. Enable Local Hybrid Search.
3. No API key is required.

## Build From Source

Recommended environment:

- Flutter 3.44.1 or newer
- Dart 3.12.1 or newer
- Android SDK/NDK for Android builds

Common commands:

```powershell
flutter pub get
flutter test test/core/providers/mcp_provider_builtin_test.dart test/kelivo_github_mcp_server_test.dart
flutter build apk --release --target-platform android-arm64
```

The repository does not include signing secrets. Configure your own `android/key.properties` or Android signing workflow before publishing APKs.

## Security Notes

- 神经权能网关 is a high-permission capability and is disabled by default. Destructive, overwrite, and batch import operations remain confirmation-driven and undoable where supported.
- GitHub write tools can modify remote repositories; use least-privilege tokens.
- Do not commit tokens, secrets, keystores, `android/key.properties`, build caches, or APK outputs.
- AGPL-3.0 obligations apply when distributing modified builds.

## Documentation

- [Chinese README](README_ZH_CN.md)
- [Kelivo Plus change notes](docs/KELIVO_PLUS_CHANGES_ZH.md)
- [Android installation and coexistence guide](docs/ANDROID_INSTALLATION_ZH.md)
- [Release notes](docs/RELEASE_NOTES_1.1.17_PLUS.md)
- [Search upgrade notes](docs/KELIVO_SEARCH_UPGRADE_NOTES.md)

## Acknowledgements

- Original project: [Chevey339/kelivo](https://github.com/Chevey339/kelivo)
- UI inspiration: [RikkaHub](https://github.com/re-ovo/rikkahub)

## License

Kelivo Plus is licensed under AGPL-3.0. See [LICENSE](LICENSE) for details.
