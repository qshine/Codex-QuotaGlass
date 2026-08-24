# QuotaGlass

QuotaGlass is a small native macOS desktop ornament that mirrors the most constrained Codex/Work usage window as an hourglass.

The app reads quota information through the locally installed official Codex App Server. It never reads browser cookies, ChatGPT databases, or authentication tokens.

## Requirements

- Apple Silicon Mac
- macOS 14 or newer
- The official ChatGPT/Codex desktop app installed and signed in
- Swift 6 toolchain (Xcode Command Line Tools is sufficient for local builds)

## Build and test

```bash
./Scripts/test.sh
swift build
./Scripts/package-app.sh
open .build/app/QuotaGlass.app
```

`swift test` remains the standard test target and compile check. On a machine with only Command Line Tools, Apple does not include the `xctest` launcher, so `Scripts/test.sh` also runs the same critical mapping, protocol, stale-state, backoff, reset, and mock-provider checks through a standalone runner (19 assertions). Full Xcode runs the Swift Testing suites normally.

The packaged app is ad-hoc signed for local use. A Developer ID identity and a notarytool keychain profile are required for public distribution.

## Data behavior

- A live App Server notification triggers an immediate full quota refresh.
- A 45-second poll is the fallback.
- A cross-path process lock guarantees one ornament even if another copy is launched.
- Hold the left mouse button anywhere on the card to move it; use the right-click menu for actions. The normalized screen position is restored later.
- If data is older than 60 seconds, QuotaGlass marks it as stale instead of presenting it as current.
- When multiple limits exist, the smallest remaining percentage wins. Ties prefer the later reset, then the primary window.

## Privacy

QuotaGlass has no analytics and no cloud service. Only normalized quota percentages, reset times, window position, and launch-at-login preference are held locally.

## Packaging and notarization

```bash
QUOTAGLASS_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/package-app.sh release
./Scripts/notarize.sh .build/app/QuotaGlass.app YOUR_NOTARYTOOL_PROFILE
```

The notarization script submits a temporary ZIP and staples the accepted ticket to the app.
