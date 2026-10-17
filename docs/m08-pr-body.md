## M08 — Outfit suggestions and explanations

### Behavior

- Generates owned-item outfit suggestions from deterministic category rules,
  manual occasion, style preferences and recent wear.
- Rejects invalid model ranking IDs and falls back to rules.
- Adds concise explanations plus separate Save outfit and Wear today actions.

### Verification

- [x] Simulator build passes.
- [x] Unit-test target passes on the iPhone Duo iOS 27.1 simulator (26 tests).
- [ ] UI navigation smoke test cannot locate the simulator tab bar.
- [ ] Device ranking evaluation and explicit Wear today validation remain
  required before merge.
- [ ] M06 does not yet provide a production inference loader for model ranking.

### Evidence

See docs/m08-evidence.md.
