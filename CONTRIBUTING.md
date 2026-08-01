# Contributing to Kelivo Plus

Kelivo Plus is a secondary-development fork of [Chevey339/kelivo](https://github.com/Chevey339/kelivo). Contributions should preserve upstream attribution, AGPL-3.0 licensing, and the security boundary around high-permission assistant tooling.

## Development Setup

```powershell
flutter pub get
flutter test
```

For focused work, prefer targeted tests near the changed module. Some vendored dependency tests may require separate dependency setup, so app-level targeted tests are usually more reliable during feature development.

## Commit Guidelines

- Keep feature areas separated when possible: App Control, Skills, MCP, GitHub, Search, UI, docs.
- Do not commit generated build output, local SDK junctions, APK/AAB files, signing files, or local credentials.
- Keep user-visible tool descriptions localized when adding new built-in tools.
- Add or update tests for MCP tool schemas, high-permission actions, importers, and search parsing/filtering.

## Security Rules

- Never commit GitHub tokens, API keys, private keys, keystores, or `android/key.properties`.
- App Control Agent changes must remain opt-in per assistant.
- Write-capable tools should validate parameters before calling external APIs.
- GitHub tools should follow GitHub API payload rules and avoid sending unrelated action fields.

## Release Checklist

1. Update `pubspec.yaml` version.
2. Run focused tests for changed modules.
3. Build and sign APK outside Git history.
4. Verify APK signature and SHA256.
5. Push source changes.
6. Create a GitHub Release and upload APK as a release asset.
