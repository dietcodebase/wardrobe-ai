# M08 outfit-suggestion evidence

Status: implementation in progress; physical-device and ranking-quality acceptance
remain pending.

## Implemented behavior

- Suggestions use only item IDs owned by the local wardrobe. A deterministic
  candidate builder combines a top and bottom or a one-piece, adding at most one
  outerwear, shoe, and accessory item.
- Sparse wardrobes fall back to a single owned garment. Recent wear reduces a
  candidate score, while manual occasion, color and saved style preferences can
  increase it.
- A ranking integration can only reorder the bounded candidate ID set. Unknown
  and repeated IDs are discarded, and rule order remains the fallback when no
  ranker is configured. The store accepts a ranker dependency at the
  recommendation boundary.
- The Stylist tab accepts manual occasion context, shows concise item-grounded
  explanations, and provides separate Save outfit and explicit Wear today
  actions. Saving never records a wear event.
- Weather and calendar are explicitly described as manual context until M10
  and M11.

## Verification

- Build passed on 17 October 2026 using the project’s iOS simulator scheme.
- The unit-test target passed on the iPhone Duo iOS 27.1 simulator on
  17 October 2026: 26 tests, zero failures. The recommendation tests cover
  top/bottom and one-piece candidates, sparse wardrobes, invalid ranking
  responses, anchored suggestions, optional alternatives, and ten fixed
  wardrobe/context cases.
- The UI navigation smoke test failed because XCTest could not locate the
  simulator tab bar. This remains an outstanding UI verification result.

## Still required for milestone acceptance

Compare the displayed order and explanation quality on at least ten fixed
wardrobe/context cases on the intended device. Record ranking quality
separately from retrieval similarity. Exercise save and Wear today against the
real app and confirm duplicate taps do not create duplicate wear events. The
qualified M01 local route must remain available; otherwise the deterministic
rules and manual wardrobe continue without a model ranker. M06 currently has
no production inference loader, so a real local model ranker cannot be
configured until that prerequisite is implemented.
