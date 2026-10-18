# On-device privacy gate

Updated 19 October 2026. The v1 rule keeps wardrobe photos and prompts on the
phone. The merged remote Ollama experiment violated that rule when a server URL
was configured.

This change restores the v1 fallback while M01 device qualification is open:

- Production Ollama transport rejects requests before `URLSession` runs.
- Previously saved endpoints are ignored; remote server controls are removed.
- Capture suggestions and demo photo tagging default to on-device Apple Vision,
  with review and correction before a garment is saved.
- Outfit candidates and stylist replies use owned-item rules and local storage.
- Model provisioning displays the real M01 gate rather than marking device
  qualification as passed.

The disabled Ollama client types and fixture tests remain for code history; they
are not a production inference path. Apple Vision labels are an interim local
fallback, not a passed Gemma 4 vision demo. E2B text/image, embedding and audio
still require the iPhone 17 report and Instruments trace before on-device Gemma
can be enabled or advertised.

## Verification

- Xcode 27.1 generic iOS Simulator app build: passed.
- Arm64 iOS Simulator `StylistChatTests`: 12 passed, 0 failed.
- Broader 39-test slice: 35 passed, 4 failed in decoder, legacy Ollama fixture,
  demo seed photo and timestamp round-trip tests. These failures remain open in
  the integrated validation tracker; none of the four failures exercises the
  production transport or saved-endpoint guard.
- Physical-device privacy and AI behavior: pending.
