# Security Policy

Kelivo Plus contains high-permission local and remote automation features. Please report sensitive issues privately when possible.

## Sensitive Areas

- App Control Agent configuration edits.
- Built-in file tools.
- GitHub write tools.
- Token, secret, and variable management.
- Android signing and release packaging.

## Safe Configuration

- Keep App Control disabled unless the assistant is trusted.
- Use least-privilege GitHub tokens.
- Do not paste secrets into prompts unless the model/provider is trusted for that data.
- Keep signing keys outside the repository.

## Public Repository Hygiene

The repository intentionally ignores local signing files, build output, APK/AAB files, local SDK paths, and app-specific secret files. Release APKs should be uploaded through GitHub Releases rather than committed to Git.
