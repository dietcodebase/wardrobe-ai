# M15 mirror fit-check demo guide

## Scope

The mirror flow is a still-photo check for a saved outfit. It keeps the photo in
the sheet only, offers comments about the selected clothing and supplied context,
and links only to replacement garments that are currently in the local wardrobe.
It does not make body measurements, body judgments, or continuous-video claims.

## Reproducible demo

1. Start from a fresh local wardrobe with at least two tops, one bottom, and two
   saved outfits. Add a second top to demonstrate an owned swap.
2. Open **Outfits** and choose **Mirror fit check**.
3. Select a saved outfit, optionally enter an occasion, then capture or choose a
   full-frame still photo.
4. Confirm the clothing check names only the saved garments and the supplied
   context. It must not evaluate the person's body.
5. Open an owned-item swap and confirm the displayed replacement still exists in
   the wardrobe. Repeat with an outfit that has no same-category alternative and
   confirm the explicit no-swap outcome.
6. Close the sheet, relaunch the app, and confirm the photo was not saved by the
   mirror flow. Saved wardrobe photos and outfits remain unchanged.

## Support matrix

| Capability | Current state |
|---|---|
| Still photo from library | Implemented; device permission path needs final validation |
| Still photo from camera | Implemented; requires camera permission and a physical device |
| Clothing-only local feedback | Implemented from selected wardrobe items and optional context |
| Verified owned-item swaps | Implemented when a same-category alternative exists |
| Weather-aware wording | Engine supports supplied weather context; release wiring/measurement pending |
| Visual model critique | Not claimed until M01 generation/vision qualification passes |
| Continuous video inference | Out of scope |

## Assets and dependencies

Use only synthetic, licensed, or operator-owned demo photos. Do not place
personal photos, model weights, API keys, or runtime databases in Git. The app
uses the existing Photos picker/camera APIs and local wardrobe database; its
Swift package dependencies remain GRDB.swift and LiteRT-LM as pinned in the
project. Event or hackathon track eligibility is intentionally not claimed here:
confirm it against the official event rules before submission.
