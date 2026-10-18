# Wardrobe AI

An iOS SwiftUI wardrobe app under incremental development. The M00 shell has
Wardrobe, Outfits and Stylist tabs with honest placeholder screens. Storage,
capture and AI arrive in later [roadmap milestones](ROADMAP.md).

## Build and smoke test

Install full **Xcode 16.4 (16F6)** and the **iOS 18.5 simulator runtime**, then
create an **iPhone 16** simulator in Xcode's Devices and Simulators window.
The provisional minimum deployment target is iOS 18.0; runtime qualification
belongs to M01. No package manager, credentials or model downloads are needed.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/check-ios.sh
```

The script checks the exact toolchain, then runs a clean simulator build, unit
tests and UI smoke test on all three tabs. CI uses the same script with Xcode
at `/Applications/Xcode_16.4.app`. Remove a previous `build/M00.xcresult` before
rerunning; Xcode does not overwrite result bundles. Open
`WardrobeAI.xcodeproj`, choose the shared `WardrobeAI` scheme and press Run for
interactive use. Simulator builds disable signing; a real device needs a local
team and unique bundle identifier configured in Xcode. Never commit signing
credentials or user-specific project settings.

## Delivery

Read [validation](docs/PLAN-VALIDATION.md) and the [M00 evidence](docs/m00-evidence.md).
Use milestone branches and the PR template. Require the `Build and smoke tests`
check and PR review on `main` once hosting permissions are available. M00 remains
blocked until a clean build, launch and tab navigation have actually passed.

Keep models in ignored `Models/`, personal images/data in ignored `LocalData/`,
and local credentials in `.env` or `Config/Local.xcconfig`. No sample private
photos or runtime artifacts belong in this repository. Service protocols and
fakes will be introduced with their first consumer; this static shell has none.

## Remote Ollama

The Stylist can use a remote Ollama server as its default AI responder, with
`gemma4` selected by default. Enter the server URL in **Stylist → Remote AI**;
the connection design, privacy boundary, and deployment notes are in
[docs/remote-ollama.md](docs/remote-ollama.md).
