# Third-party notices

Relay is built on the work of others. This file lists the main third-party
components Relay distributes or links against, and their licenses. Each project
remains under its own license; see the linked sources for full terms.

## Backend (`relay-helper`, Go)

- **mautrix-meta** — `go.mau.fi/mautrix-meta`
  License: **GNU AGPL-3.0**. https://github.com/mautrix/meta
  Relay's helper compiles in mautrix-meta to speak Meta's non-E2EE (Lightspeed)
  protocol. Because of this, **Relay as a whole is distributed under AGPL-3.0**
  (see `LICENSE`). The mautrix license and its exceptions are preserved at
  `thirdparty/mautrix-meta/LICENSE` and `thirdparty/mautrix-meta/LICENSE.exceptions`.

- **whatsmeow** — `go.mau.fi/whatsmeow`
  License: **MPL-2.0**. https://github.com/tulir/whatsmeow
  Used for the encrypted (E2EE / WhatsApp-protocol) channel.

- **libsignal (go.mau.fi/libsignal)** — used for E2EE. See upstream for license.
- **mautrix Go utilities (go.mau.fi/util)** — MPL-2.0.
- **beeper/argo-go, beeper/poly1305** — see upstream.
- **modernc.org/sqlite** — BSD-3-Clause-style; bundled SQLite is public domain.
- **rs/zerolog** (MIT), **google/uuid** (BSD-3-Clause), **gorilla/websocket** (BSD-2-Clause),
  **coder/websocket** (ISC), **tidwall/gjson·sjson·match·pretty** (MIT),
  **vektah/gqlparser** (MIT), **yuin/goldmark** (MIT), and other transitive Go
  modules — each under its own permissive license; see `relay-helper/go.sum`
  and the respective repositories.

## App (`Relay`, Swift / macOS)

- **Sparkle** — https://github.com/sparkle-project/Sparkle
  License: permissive (MIT-style, with bundled components under their own terms).
  Powers in-app automatic updates. Bundled in `Relay.app/Contents/Frameworks`.

## Services

- **GIPHY** — GIF search/sending uses the GIPHY API. Use is subject to the
  GIPHY API Terms of Service (https://developers.giphy.com/). The key shipped in
  source is a public/community key intended for low-volume personal use.

---

Relay is an independent project and is **not affiliated with, authorized, or
endorsed by Meta Platforms, Inc., Facebook, Messenger, or WhatsApp**. All
trademarks are the property of their respective owners.
