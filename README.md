# Relay

A premium, native **macOS** client for Facebook Messenger — built to *replace*
Messenger, not wrap it. Relay is a real SwiftUI app (Liquid Glass) backed by a Go
helper that speaks Meta's actual protocols, so it feels like a first-class Mac app:
fast, keyboard-driven, with a glassy continuous window, per-chat colors and
wallpapers, scheduled send, snooze, on-device translation, Touch ID lock, a menu-bar
companion, Siri/Shortcuts intents, and full local message history with search.

> **Relay is an independent project. It is not affiliated with, authorized, or
> endorsed by Meta Platforms, Inc., Facebook, Messenger, or WhatsApp.**

---

## ⚠️ Read this before you use Relay

Relay is an **unofficial** client. It logs into your real Facebook account using
the same kind of session the website uses, via reverse-engineered protocols
(the same ones the [mautrix-meta](https://github.com/mautrix/meta) and
[whatsmeow](https://github.com/tulir/whatsmeow) bridges use).

- **Your account could be rate-limited, restricted, or banned.** Meta does not
  permit third-party clients. Use Relay only if you accept that risk. Don't use it
  on an account you can't afford to lose.
- **Your session is the keys to your account.** Relay stores your Facebook session
  in the macOS **Keychain**, on your Mac only. It is never sent anywhere except to
  Meta's own servers, exactly as a browser would. Relay has no servers and collects
  nothing.
- **It can break at any time.** Meta changes its protocol without notice.

By downloading and using Relay you accept these risks. There is **no warranty** (see
the license).

---

## Install

1. Download the latest `Relay.zip` from the [**Releases**](../../releases) page.
2. Unzip and drag **Relay.app** to `/Applications`.
3. Open it. The build is Apple **notarized**, so it runs without Gatekeeper
   warnings.
4. On first launch you'll get a short welcome + a Facebook sign-in window. Log in
   normally (password, 2FA, checkpoints all work). That's it.

Relay keeps itself up to date — when a new version ships you'll see an **Update**
prompt inside the app; one click installs it and relaunches. (Powered by Sparkle.)

## Compatibility

Relay runs on **macOS 13 Ventura or later**, on both **Apple Silicon and Intel**
(the app and its backend are universal binaries). Newer features light up
automatically on newer systems — older Macs still get a fully working app:

| Feature | macOS 13 (Ventura) | macOS 14 (Sonoma) | macOS 15 (Sequoia) | macOS 26 (Tahoe) |
|---|:--:|:--:|:--:|:--:|
| Core messaging, history, search, media | ✅ | ✅ | ✅ | ✅ |
| Liquid Glass UI | frosted-material look | frosted | frosted | ✅ glass |
| Return-to-send key handling | ✅ (Send button) | ✅ | ✅ | ✅ |
| On-device translation | — | — | ✅ | ✅ |
| Jump-to-bottom “new messages” pill | — | — | ✅ | ✅ |

On macOS 13–15 the glass surfaces render as a frosted material instead of true
Liquid Glass; everything else works the same.

## Features

- Continuous Liquid-Glass window, fluid send/receive animations, Messenger-style
  message grouping and read/seen indicators.
- Per-chat **accent colors** and **wallpapers**; **nicknames** per conversation.
- **Scheduled send**, **snooze**, **reactions**, replies, edit/unsend, forwarding,
  **saved messages**, drag-and-drop and multi-image sending, voice notes, GIFs +
  an emoji picker.
- **On-device translation** (single message or whole conversation).
- **In-chat search** + global full-text search over your entire local history.
- **Touch ID / password lock**, menu-bar companion with unread count, inline-reply
  notifications, **Siri / Shortcuts** intents.
- Local **SQLite** history with windowed loading (never floods memory), and a
  one-click **conversation export** to a text file.

## Build from source

Requires macOS 26+, Xcode 26+, Go 1.23+, and [`xcodegen`](https://github.com/yonsm/XcodeGen)
(`brew install xcodegen`).

```bash
git clone <this-repo> Relay && cd Relay
scripts/run-native.sh      # builds the Go helper + app, signs locally, installs, launches
```

To produce a notarized, shareable build (needs an Apple Developer ID + notary
credentials — see [`RELEASE.md`](RELEASE.md)):

```bash
scripts/release.sh         # → dist/Relay.app and dist/Relay.zip
```

## How it works

- **`RelayNative/`** — the SwiftUI macOS app (the source folder name predates the
  rename to "Relay").
- **`relay-helper/`** — a Go daemon the app launches and talks to over stdio
  (line-delimited JSON). It uses `mautrix-meta` (non-E2EE / Lightspeed) and
  `whatsmeow` (E2EE) to decode Meta's real protocol.
- **`thirdparty/mautrix-meta`** — vendored fork (referenced via a Go `replace`).

## License

Relay is licensed under the **GNU Affero General Public License v3.0** — see
[`LICENSE`](LICENSE). This is required because Relay statically incorporates
AGPL-3.0 code (mautrix-meta); the complete corresponding source must remain
available. Third-party components and their licenses are listed in
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).

## Acknowledgments

Relay stands on the shoulders of [mautrix-meta](https://github.com/mautrix/meta) and
[whatsmeow](https://github.com/tulir/whatsmeow) by Tulir Asokan and contributors,
and uses [Sparkle](https://sparkle-project.org) for updates. Thank you.
