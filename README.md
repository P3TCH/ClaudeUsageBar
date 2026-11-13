# UsageBar

A macOS menu bar app that shows your Claude Code and Codex usage limits:

- **Claude**: session (5-hour), weekly (all models), weekly Fable, plus any other model-scoped weekly limits the server reports.
- **Codex**: session (5-hour) and weekly.

You choose which of these appear in the menu bar (gear icon in the popover). They show as small numbers stacked two per column (for example weekly above Fable); open the popover for the labelled details. The popover always shows everything, with reset times.

## Build and run

Requires macOS 14+ and Xcode (Swift 6).

```sh
./scripts/build-app.sh          # builds build/UsageBar.app
open build/UsageBar.app
cp -R build/UsageBar.app /Applications/   # optional
```

The script stamps the installed SDK version onto the binary, so macOS 26 and later give the app the current system appearance (Liquid Glass) instead of the legacy one.

Tests: `swift test`

## Releases

Push a version tag to cut a release:

```sh
git tag v0.0.1 && git push origin v0.0.1
```

The `Release` workflow runs the tests, builds the app, and publishes a GitHub Release with `UsageBar-<version>-macos-arm64.zip` (plus a `.sha256`). The tag's version becomes the app version.

To install a downloaded release, unzip it and move `UsageBar.app` to `/Applications`. The build is ad-hoc signed, not notarized, so Gatekeeper blocks it on first launch. Run this once, then open it:

```sh
xattr -dr com.apple.quarantine /Applications/UsageBar.app
```

To stamp a version on a local build: `VERSION=1.2.3 BUILD_NUMBER=42 ./scripts/build-app.sh`

## Sign-in

Each service uses its own browser OAuth login (PKCE), separate from the Claude Code and Codex CLIs, so the app never invalidates the CLIs' tokens. Tokens are stored in the macOS Keychain under the service `com.usagebar.app`.

- Codex sign-in needs port 1455 free. Close any running `codex login` first.
- After a rebuild, macOS may ask once whether UsageBar can read its Keychain item, because ad-hoc signing changes the app's signature. Choose **Always Allow**.

## Caveats

The usage endpoints (`api.anthropic.com/api/oauth/usage`, `chatgpt.com/backend-api/wham/usage`) are undocumented. They are the ones the official CLIs call, and they can change without notice. Design notes: `docs/superpowers/specs/2026-11-04-usagebar-design.html`.
