# Remote Ollama stylist

## Design

The Stylist tab uses a remote Ollama server as its preferred inference provider.
`gemma4` is the default model name. The connection is deliberately configured on
the device rather than baked into the app: an iPhone's `localhost` cannot reach
the computer running Ollama, and the deployment's remote URL is environment
specific.

The configuration is stored in the app's preferences:

- **Ollama server URL**: an HTTP(S) server root, for example
  `https://ollama.example.net`, or an `/api` base URL.
- **Model**: defaults to `gemma4`.

Every chat message uses `POST /api/chat` with `stream: false`. The app sends a
small, explicit context containing only garment names, categories, colors, and
upcoming in-app plan labels. Images, device data, and wear history are not sent.
The system instruction constrains the model to that context and prevents it from
claiming that it recorded wear.

## Behavior and failure mode

When a valid endpoint is configured, Ollama is the first and default responder.
If it is unavailable or sends an invalid response, the app says that Gemma 4 is
unavailable and returns the existing deterministic wardrobe answer so that core
wardrobe actions keep working. If no endpoint has been entered yet, the same
offline responder is used without a misleading network error.

Use HTTPS for a remote server in production. Plain HTTP may be suitable only for
a trusted development LAN and may require an explicit App Transport Security
exception in the host app.

## Setup

1. Expose an Ollama server reachable from the iPhone and make sure the server
   has a model addressable as `gemma4`.
2. In **Stylist → Remote AI**, enter its full URL and leave **Model** as
   `gemma4` unless your server uses a different tag.
3. Send a stylist message. The UI identifies the remote responder as preferred;
   any connection failure is shown in the answer before the offline fallback.

No API key is sent by this integration. Put authentication, TLS, and network
access control in front of a publicly reachable Ollama server.
