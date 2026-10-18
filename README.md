# Wardrobe AI

An iOS SwiftUI wardrobe app with garment capture, saved outfits, contextual
recommendations and a stylist interface. Feature code through M15 is merged;
the [roadmap](ROADMAP.md) and [validation tracker](docs/final-validation.md)
show the remaining device and release gates. The [mind map](docs/mindmap.md)
links the feature groups to milestone cards.

## Build and smoke test

Use full Xcode with an installed iOS simulator runtime. The app project still
targets iOS 18.0; physical iPhone 17 and LiteRT-LM support must be measured by
the [qualification probe](Qualification/README.md). Model weights, signing and
credentials are not required for a simulator build.

```sh
xcodebuild -project WardrobeAI.xcodeproj -scheme WardrobeAI \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData/WardrobeAI CODE_SIGNING_ALLOWED=NO build
```

The legacy `scripts/check-ios.sh` still pins Xcode 16.4 and an iPhone 16/iOS 18.5
simulator for its original M00 CI gate. Open `WardrobeAI.xcodeproj`, choose the
shared `WardrobeAI` scheme and press Run for interactive use. A real device needs
local signing configured in Xcode. Never commit signing credentials or
user-specific project settings.

## Delivery

Read [validation](docs/PLAN-VALIDATION.md) and the
[final acceptance tracker](docs/final-validation.md). Use milestone branches and
the PR template for follow-up fixes. A simulator build is compilation evidence,
not an iPhone 17 on-device AI pass.

Keep models in ignored `Models/`, personal images/data in ignored `LocalData/`,
and local credentials in `.env` or `Config/Local.xcconfig`. No sample private
photos or runtime artifacts belong in this repository. Service protocols and
fakes will be introduced with their first consumer; this static shell has none.

## Remote Ollama

The current Stylist code can send wardrobe context to a user-configured remote
Ollama server. This path conflicts with the v1 on-device privacy requirement in
the implementation plan and remains a [release blocker](docs/final-validation.md).
Its current behavior is documented in [docs/remote-ollama.md](docs/remote-ollama.md).
