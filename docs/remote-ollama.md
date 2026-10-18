# Archived remote Ollama integration

The remote Ollama experiment is disabled in the v1 app because the product
contract keeps wardrobe images and stylist prompts on the device. Existing
saved server URLs are ignored. The production `URLSessionOllamaTransport`
rejects requests before any network call, and the UI no longer offers a remote
server setting.

The older client and its fixture-based tests remain in source history for review.
They are not an accepted inference route or a fallback for failed on-device
qualification. The current stylist uses owned-item rules; automatic garment
tagging uses on-device Apple Vision with editable results. The iPhone 17
LiteRT-LM generation, image, embedding and audio gates remain in
[final validation](final-validation.md).
