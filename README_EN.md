# Kelivo Plus

[简体中文](README.md) | English

Kelivo Plus is a modified open-source build based on [Chevey339/kelivo](https://github.com/Chevey339/kelivo). The original Kelivo is a cross-platform Flutter LLM chat client. This fork keeps the original chat, model provider, multimodal, MCP, search, and mobile/desktop foundations, then adds stronger mobile agent control, built-in tools, Skills, local hybrid search, and writable GitHub MCP tooling.

> Fork notice: this repository is not the official upstream repository. It is a secondary development build based on the original Kelivo project. Original copyright, acknowledgements, and license terms are preserved. This project remains licensed under AGPL-3.0.

## What Changed From Upstream

| Area | Upstream Kelivo | Kelivo Plus |
| --- | --- | --- |
| Assistant configuration | Mostly manual settings pages | Adds a neural capability gateway that can import and edit configuration from chat after explicit assistant authorization |
| Assistant permissions | Standard assistant settings | Adds an opt-in permission switch for app configuration control |
| Skills | No standalone reusable Skills workflow | Adds Skill model, importer, Skills page, assistant binding, and trigger-based injection |
| Built-in MCP | MCP integration with built-in Fetch | Adds built-in Files, Images, GitHub, and in-memory MCP services |
| GitHub tools | Read-oriented or basic tooling | Adds grouped write-capable tools for repos, files, issues, PRs, releases, actions, secrets, and variables |
| Search | Multiple API-backed providers | Adds API-key-free local hybrid search using Bing Local, DuckDuckGo, Baidu, Sogou, and 360 with filtering/ranking |
| Mobile import flow | Mostly manual import | Supports chat-driven import from text, previous generated content, shared files, and user instructions |
| Tool UX | Tool list can be noisy | Adds Chinese visible tool descriptions and grouped tool surfaces |

## Highlights

### Neural Capability Gateway

- Enable per assistant through the app configuration-control permission switch.
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

### Mobile Reasoning Slider

- Replaces the mobile reasoning bottom sheet with a compact slider-first control.
- Keeps existing `thinkingBudget` storage and provider request mapping.
- Adds the `Ultracode` visual preset for the highest available reasoning level, with right-to-left purple particle flow.
- Keeps Off, Auto, and Custom as secondary actions below the slider.

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

- Latest Release page: [Kelivo Plus 1.1.17+9015](https://github.com/MuMu-0604/kelivo/releases/tag/v1.1.17-plus.9015)
- Direct Android universal APK: [Kelivo_android_1.1.17+9015_reasoning-help-right-particles_coexist_fixedsign_universal.apk](https://github.com/MuMu-0604/kelivo/releases/download/v1.1.17-plus.9015/Kelivo_android_1.1.17%2B9015_reasoning-help-right-particles_coexist_fixedsign_universal.apk)

The `1.1.17+9015` APK is a coexistence build. It uses Android package name `com.psyche.kelivo.sliderpreview` and launcher label `Kelivo Slider`, so it can be installed beside upstream Kelivo (`com.psyche.kelivo`).

- It keeps separate Android app data from the upstream package.
- It can update older coexistence builds only when the signing certificate matches and the version code is not lower.
- If Android reports a signature conflict, remove the older non-coexistence or mismatched-signed Kelivo Plus build, then install the 9015 APK again.
- Migrate data through backup/import instead of directly sharing private app data.

To build a coexistence variant from source, keep the same codebase and pass app identity overrides:

```powershell
flutter build apk --release `
  --dart-define=APP_FLAVOR=slider `
  -PkelivoApplicationId=com.psyche.kelivo.sliderpreview `
  -PkelivoAppLabel="Kelivo Slider"
```

### Configure Models

1. Open Kelivo Plus.
2. Add a model provider such as OpenAI, Gemini, Anthropic, or another compatible endpoint.
3. Select the model in chat and start using it.

### Enable the Neural Capability Gateway

1. Open an assistant settings page.
2. Enable the app configuration-control permission switch.
3. Ask the assistant to import or edit a supported configuration target from chat.
4. Review the generated action and undo recent changes when needed.

### Use Skills

1. Open the Skills page.
2. Create or import a Skill.
3. Bind it to an assistant, or configure trigger keywords.
4. Use the assistant normally; matching Skills are injected into the conversation context.

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
flutter test test/features/chat/widgets/reasoning_budget_sheet_test.dart
flutter build apk --release --target-platform android-arm64
```

The repository does not include signing secrets. Configure your own `android/key.properties` or Android signing workflow before publishing APKs.

## Security Notes

- The neural capability gateway is a high-permission capability and is disabled by default. Destructive, overwrite, and batch import operations remain confirmation-driven and undoable where supported.
- GitHub write tools can modify remote repositories; use least-privilege tokens.
- Do not commit tokens, secrets, keystores, `android/key.properties`, build caches, or APK outputs.
- AGPL-3.0 obligations apply when distributing modified builds.

## Documentation

- [Simplified Chinese README](README.md)
- [Kelivo Plus change notes](docs/KELIVO_PLUS_CHANGES_ZH.md)
- [Android installation and coexistence guide](docs/ANDROID_INSTALLATION_ZH.md)
- [Release notes](docs/RELEASE_NOTES_1.1.17_PLUS.md)
- [Search upgrade notes](docs/KELIVO_SEARCH_UPGRADE_NOTES.md)

## Acknowledgements

- Original project: [Chevey339/kelivo](https://github.com/Chevey339/kelivo)
- UI inspiration: [RikkaHub](https://github.com/re-ovo/rikkahub)

## License

Kelivo Plus is licensed under AGPL-3.0. See [LICENSE](LICENSE) for details.
