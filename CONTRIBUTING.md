# Contributing

RayNote uses Swift, AppKit, and SwiftUI, with no third-party Swift package dependencies.

## Get started

Use macOS 14 or later with Swift 6 or later. Build and run instructions are in the [README](README.md).

Run `swift test` before submitting a change. For packaging changes, also run `./scripts/build-app.sh` and `codesign --verify --strict dist/RayNote.app`. The macOS CI workflow runs these checks; its hosted result is only available after the repository is published.

Use `./scripts/build-qa-app.sh` for UI work. Its separate bundle and `.build/qa-library` keep test notes away from the normal library. Do not use personal notes, credentials, or confidential screenshots in fixtures, issues, or pull requests.

## Changes

Keep changes focused and describe the problem, resulting behavior, and verification. Add regression tests for data loss, parsing, selection, undo, and shortcut issues. For visual changes, include light and dark screenshots using synthetic notes. Preserve native text editing and the original Markdown source.

Do not commit build output, local note libraries, signing keys, or access tokens. Review `git diff --cached` before committing. If Gitleaks is installed, check history with:

```sh
gitleaks git . --log-opts='--all --full-history' --redact
```

Report suspected vulnerabilities without posting credentials or private note contents. Provide a minimal reproduction using synthetic data.
