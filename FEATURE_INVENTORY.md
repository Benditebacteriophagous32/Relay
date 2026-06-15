# Relay — Messenger Replacement Feature Inventory (2026)

> A categorized feature roadmap for **Relay**, a premium native macOS (SwiftUI) Facebook Messenger client backed by a Go service speaking Meta's protocol. Goal: **fully replace** the official Messenger experience for one power user.
>
> Priority key (for "replace Messenger entirely"): **[core]** = must have to not feel broken · **[important]** = expected by a heavy user · **[nice]** = polish/delight · **[skip]** = not worth it for a single power user.

---

## Strategic context (read this first)

Meta has **vacated the desktop** entirely:

- **Dec 2025** — the native Messenger desktop apps for macOS and Windows were discontinued and pulled from the stores.
- **April 2026** — the standalone `messenger.com` web client was shut down; it now redirects to `facebook.com/messages` (messaging buried inside the full Facebook web UI).
- Phone-number-only (no linked Facebook account) sign-in no longer works on desktop at all.

**Implication for Relay:** there is currently *no* good first-party desktop Messenger. Relay isn't competing with a polished native app — it's filling a vacuum Meta created. That raises the value of the project and means "parity with the old desktop app" is a low bar; the real target is the mobile feature set plus native-Mac power features.

**Backend reality:** The proven foundation is **messagix** (the Go library inside `mautrix-meta`), which already does text/media messaging, reactions, edits, presence, typing, threads, and group ops over Meta's MQTT protocol. Everything in Part 1 marked feasible is feasible *because messagix or its protocol surface already reaches it*. The two big walls are (a) **E2EE/Secure Storage** (default-on now — see Part 1 §6) and (b) **voice/video calling** (see Part 3).

Sources: [IBTimes — Messenger desktop/messenger.com shutdown 2026](https://www.ibtimes.com.au/facebook-messenger-desktop-update-2026-5-key-things-users-must-know-after-messengercom-shutdown-1866704) · [mautrix/meta](https://github.com/mautrix/meta) · [messagix socket tasks](https://pkg.go.dev/go.mau.fi/mautrix-meta/messagix/socket)

---

# PART 1 — Official Messenger feature set (2026)

What the official Messenger app/web does that a full replacement may need to match.

## 1.1 Chat & messaging core

| Feature | Priority | Notes |
|---|---|---|
| Send/receive text DMs | **core** | The baseline; messagix does this. |
| Edit sent message (≤15 min window) | **important** | Meta caps edits at 15 minutes; replicate the window and the "Edited" marker. |
| Unsend / remove message (for everyone, anytime) + "remove for you" | **core** | Two modes: unsend-for-everyone leaves a "message was removed" tombstone; delete-for-you is local. |
| Reactions (emoji) | **core** | Long-press/hover → reaction bar; tap again to remove. |
| Custom / any-emoji reactions | **important** | Messenger lets you set custom default reactions and react with any emoji, not just the 6 defaults. |
| Reply (quote a specific message) | **core** | Inline quoted reply. |
| Forward message | **important** | Forward to one or many threads. |
| Per-message options menu | **core** | Copy, reply, forward, react, remove, report, "more." |
| Send silently / no-notification send | **nice** | Messenger has "Silent Message" (suppresses recipient notification). |
| Bump a message | **nice** | Re-surface/emphasize an existing message. |
| Mentions (@) in groups | **important** | @-mention pings a specific member; triggers a mention-notification even in muted threads. |
| Typing indicator (send) | **core** | Emit typing so the other side sees it (and conversely render incoming — see §1.5). |
| Drafts (per-thread, persistent) | **important** | Unsent text retained per conversation across launches. |
| Stickers / GIFs / animated stickers | **important** | Sticker store + GIF (Giphy/Tenor) search in composer. |
| Soundmojis | **nice** | Emoji that play a short sound. Niche; low ROI for one user. |
| Message effects / Word Effects | **nice** | Full-screen confetti/effects; "Word Effects" trigger an emoji animation on a chosen phrase. |
| Scheduled send | **important** | Send-later. (Mobile/Telegram-grade; cross-listed in Part 2 §2.14 for native UX.) |

Sources: [Messenger features](https://www.messenger.com/features/) · [TechWiser — Messenger tips/effects](https://techwiser.com/best-and-new-facebook-messenger-tips-and-tricks/) · [How to unsend in Messenger 2026](https://ucompares.com/social-media/messenger/unsending-messages-in-messenger/) · [Undo a reaction](https://www.socialappshq.com/facebook/how-to-undo-and-delete-a-reaction-on-messenger/)

## 1.2 Rich media

| Feature | Priority | Notes |
|---|---|---|
| Photo send/receive | **core** | Inline thumbnails, full viewer. |
| HD photo / video | **important** | Messenger added HD toggle; default is compressed. Match HD upload/download. |
| Video send/receive + inline playback | **core** | |
| Voice messages (audio notes) | **core** | Record, waveform, playback; widely used. |
| Video voice messages (video notes) | **nice** | Short circular video clips. |
| Files / documents | **important** | Arbitrary file attachments. |
| Shared photo/video albums in groups | **nice** | Group "albums" of media. |
| GIF / sticker (see §1.1) | **important** | |
| Quick Look / inline attachment preview | **important** | Native-Mac affordance (cross-ref Part 2 §2.11). |

Sources: [Messenger features](https://www.messenger.com/features/) · [Messenger HD video calls & media](https://about.fb.com/news/2024/11/introducing-ai-backgrounds-noise-suppression-and-more-messenger-calling/)

## 1.3 Voice & video calling (summary — full analysis in Part 3)

| Feature | Priority | Notes |
|---|---|---|
| Receive **incoming-call notification** | **important** | Achievable: call ring events flow over the same MQTT stream you already parse (precedent: mautrix-facebook surfaced a "call received" notice). |
| Show missed-call / call-event entries in thread | **important** | Render call events in the timeline even if you can't place/answer. |
| 1:1 voice call (place/answer with live media) | **skip** | Not achieved by any third-party client. Out of reach (Part 3). |
| 1:1 video call | **skip** | Same. |
| Group voice/video call | **skip** | Same. |
| Screen share | **skip** | Part of the RTC stack; out of reach. |
| HD video / AI backgrounds / noise suppression | **skip** | Meta RTC-only features. |
| **Fallback:** "Call in official app" deep-link button | **important** | Pragmatic escape hatch — hand off to the mobile app / native ringer (the same compromise Beeper makes). |

Sources: [Beeper — Messenger calls unsupported](https://help.beeper.com/en_US/chat-networks/messenger) · [mautrix-facebook CHANGELOG (call-received notice)](https://github.com/mautrix/facebook/blob/master/CHANGELOG.md) · [webrtcHacks — Facebook WebRTC teardown](https://webrtchacks.com/facebook-webrtc/)

## 1.4 Organization & inbox management

| Feature | Priority | Notes |
|---|---|---|
| Message requests (filtered inbox) | **core** | Non-friends land in "Requests"; must surface or you miss messages. |
| Spam folder | **important** | Secondary filtered bucket. |
| Archive chat | **core** | Hide a thread without deleting; un-archive on new message or manually. |
| Mark as unread | **core** | Power-user staple. |
| Mark as read / mark all read | **core** | |
| Mute conversation (timed / until) | **core** | 15 min → forever; respect on notifications. |
| Pin chats (to top) | **important** | Pin frequent threads. |
| Pin **messages** within a chat | **nice** | Pin a specific message in a thread. |
| Restrict | **nice** | Soft-block: move to requests, hide activity, no notifications. |
| Block | **important** | Hard block. |
| Report (user/message) | **nice** | Abuse reporting; rarely used by one power user. |
| Folders / filters / custom inbox views | **important** | Not strong in official Messenger — a Relay differentiator (cross-ref Part 2). |
| Marketplace chats | **skip** | Buyer/seller threads; skip unless the user trades. |

Sources: [Messenger features](https://www.messenger.com/features/) · [Birdeye — Messenger icons/symbols](https://birdeye.com/blog/facebook-messenger-icons-and-symbols/)

## 1.5 Presence, social & receipts

| Feature | Priority | Notes |
|---|---|---|
| Active status (green dot) | **important** | Show/control your own; render others'. |
| Last active ("active 12m ago / yesterday") | **important** | |
| Typing indicator (receive) | **core** | Render incoming typing. |
| Seen / read receipts (render) | **core** | "Seen" markers, per-member in groups. |
| Read-receipt controls (turn off your "seen") | **important** | Privacy lever; Meta added the toggle. |
| Delivery states (sent / delivered / seen) | **core** | Icon ladder. |
| **Notes** (24h status above chats) | **nice** | Short text status with "Mood" option. Reading them is nicer than authoring. |
| Stories (view) + cross-post from Instagram | **nice** | Stories/cross-app surface; viewing is lower-effort than authoring. |
| Cross-app (Instagram DM) interoperability | **important** | Messenger↔Instagram DMs are bridged; messagix/mautrix-meta covers Instagram DMs too — consider supporting both inboxes. |

Sources: [Active status explained](https://stripe.jhu.edu/news/why-does-active-status-disappear-on-messenger) · [Read receipts / activity status](https://beebom.com/how-turn-off-read-receipts-instagram/) · [Messenger Notes "Mood"](https://socialbee.com/blog/facebook-updates/) · [mautrix/meta (Instagram DM bridging)](https://github.com/mautrix/meta)

## 1.6 Privacy & security

| Feature | Priority | Notes |
|---|---|---|
| **End-to-end encryption (default-on)** | **core** | E2EE is now the **default** for all personal 1:1 chats and calls. **This is the single biggest backend risk** — a non-E2EE client may be unable to read/send normal DMs. Must implement Meta's E2EE (Signal-derived "Labyrinth") protocol. Track mautrix-meta's E2EE status closely. |
| Secure Storage / message restore (PIN or cloud) | **core** | E2EE history is restored via Secure Storage: 6-digit PIN, Apple/Google account, one-time code, or 40-char key. Needed to access prior history on a new device. |
| Disappearing messages (24h) | **important** | Per-thread vanish timer (24h). |
| Vanish mode / ephemeral | **nice** | Session-ephemeral messages. |
| Security alerts (new device / key change) | **important** | Surface device-added and encryption-key-change notices. |
| Screenshot detection (in E2EE/vanish) | **nice** | Notify on screenshot of disappearing media; hard to fully replicate. |
| App lock (Face/Touch ID / passcode) | **important** | Native: gate Relay behind biometrics. |

Sources: [Cyberly — Messenger default E2EE](https://www.cyberly.org/news/facebook-messenger-rolls-out-default-end-to-end-encryption-what-it-means-for-your-privacy/) · [ExpressVPN — Secret Conversations replaced by default E2EE](https://www.expressvpn.com/blog/secret-conversation-messenger/) · [Messenger Help — restore E2EE chats](https://www.facebook.com/help/messenger-app/431055522328649) · [mautrix/meta E2EE issue #7](https://github.com/mautrix/meta/issues/7)

## 1.7 Customization

| Feature | Priority | Notes |
|---|---|---|
| Chat themes / colors (per-thread) | **important** | Per-conversation theme/gradient; render incoming theme, let user set. |
| AI-generated chat themes (Meta AI) | **nice** | Meta AI can generate themes (rolled to EU etc.). Render, don't necessarily author. |
| Custom default emoji per chat | **nice** | Per-thread quick-reaction emoji. |
| Nicknames (per-member) | **important** | Custom display names within a thread. |
| Chat-specific notification sounds | **nice** | Per-thread sound; pairs well with native notif customization. |

Sources: [Messenger features](https://www.messenger.com/features/) · [SocialBee — Meta AI themes](https://socialbee.com/blog/facebook-updates/)

## 1.8 Group management

| Feature | Priority | Notes |
|---|---|---|
| Create group | **core** | |
| Add / remove members | **core** | |
| Group name / photo | **core** | |
| Group description | **nice** | |
| Admin roles | **important** | Promote/demote admins; admin-only actions. |
| Member approval / join requests | **nice** | Gate new joins. |
| Invite links | **important** | Join-by-link. |
| Member permissions (who can edit/add) | **nice** | Granular group controls. |
| Leave group | **core** | |
| Group albums (see §1.2) | **nice** | |

Sources: [Messenger features](https://www.messenger.com/features/) · [messagix socket tasks (CreateThread, group ops)](https://pkg.go.dev/go.mau.fi/mautrix-meta/messagix/socket)

## 1.9 Communities, channels & broadcast

| Feature | Priority | Notes |
|---|---|---|
| Broadcast channels (follow / read) | **nice** | One-to-many creator channels; consuming is lower-effort than running one. |
| Broadcast channel polls / voice notes / "Prompt" AI | **skip** | Creator-side tooling; out of scope for a single consumer. |
| Communities | **nice** | Topic/creator communities; render membership, low priority. |

Sources: [TechTimes — broadcast channels expand](https://www.techtimes.com/articles/297719/20231018/metas-broadcast-channels-expand-facebook-messenger.htm) · [Izoate — broadcast channels 2026](https://www.izoate.com/blog/facebook-broadcast-channels-2026-the-ultimate-guide-for-creators-brands/)

## 1.10 Interactive & utility

| Feature | Priority | Notes |
|---|---|---|
| Polls (in groups) | **nice** | Create/vote in a group poll. |
| Events / plans | **nice** | Lightweight group event planning. |
| Shared / live location | **nice** | Send static or live location. |
| Payments / send money | **skip** | Region-limited, payment-rails heavy; skip for one user. |
| In-chat search (within a thread) | **core** | Find within a conversation. |
| Global search (across all chats/people) | **core** | Cross-thread search — and a Relay strength area (Part 2 §2.6). |
| Starred / saved messages | **important** | Save messages for later (Messenger's saved-messages surface). Pairs with native bookmarking. |

Sources: [Messenger features](https://www.messenger.com/features/) · [Izoate — channel polls](https://www.izoate.com/blog/facebook-broadcast-channels-2026-the-ultimate-guide-for-creators-brands/)

## 1.11 AI features

| Feature | Priority | Notes |
|---|---|---|
| Meta AI in-chat (Q&A, suggestions) | **skip** | Server-side Meta feature; substitute your own LLM if desired rather than replicate Meta AI. |
| AI image generate/edit/animate in chat | **skip** | Meta-server-bound. |
| AI smart replies / suggested replies | **nice** | Could be reimplemented locally with an on-device/your-own model — a Relay differentiator rather than a parity item. |
| AI chat themes | **nice** | See §1.7. |

Sources: [SocialBee — Meta AI in Messenger](https://socialbee.com/blog/facebook-updates/) · [iDropNews — Messenger AI upgrades](https://www.idropnews.com/news/facebook-messenger-is-getting-some-huge-upgrades/203732/)

---

# PART 2 — Power-user / native-Mac features the official app LACKS

The official Messenger desktop offering was an Electron wrapper — and it's now **discontinued entirely**, so *every* item below is greenfield differentiation. Standout reference apps noted per feature.

## 2.1 Command palette + quick chat switcher (Cmd+K) — *highest leverage*

| Feature | Priority | Notes / reference |
|---|---|---|
| `⌘K` fuzzy chat switcher (recents first, arrow+Enter) | **core** | Universal muscle memory: Slack/Discord Quick Switcher, Beeper `⌘K`, Telegram `⌘K`. |
| `⌘⇧K` / `⌘P` command palette of **verbs** (mark read, snooze, mute, schedule, search-this-thread) | **important** | Raycast/Things pattern — actions on results, aliases, per-command hotkeys. |
| Global summon hotkey (bring switcher/compose forward from any app) | **important** | Things Quick Entry / Raycast model. |

Refs: [Beeper shortcuts](https://blog.beeper.com/2023/08/17/power-moves-beepers-keyboard-shortcuts/) · [Discord Quick Switcher](https://support.discord.com/hc/en-us/articles/115000070311-Quick-Switcher) · [Slack keyboard nav](https://slack.com/help/articles/115003340723-Navigate-Slack-with-your-keyboard) · [Raycast aliases & hotkeys](https://manual.raycast.com/command-aliases-and-hotkeys) · [Things Quick Entry](https://culturedcode.com/things/support/articles/2249437/)

## 2.2 Global shortcuts + per-thread keyboard navigation

| Feature | Priority | Notes |
|---|---|---|
| Full no-mouse inbox navigation | **core** | Steal Beeper's vocabulary: `⌘U` jump to unread, `⌘⇧U` mark unread, archive, `⌘;` inbox/archive toggle, `↑` edit last sent. |
| **Navigate without marking read** (Esc → arrows → Enter) | **important** | Power-user detail most apps miss; lets you scan without firing read receipts. |
| Jump-to-folder hotkeys (`⌘1–5`) | **nice** | Telegram model. |
| Reply-to-recent / quick-react via keyboard | **nice** | `⌘⇧↑/↓`; Tapback-style number keys. |

Refs: [Beeper shortcuts](https://blog.beeper.com/2023/08/17/power-moves-beepers-keyboard-shortcuts/) · [Telegram Desktop shortcuts](https://blog.invitemember.com/2024-telegram-desktop-shortcuts-effortless-efficiency/)

## 2.3 Multi-window

| Feature | Priority | Notes |
|---|---|---|
| Tear-off conversation into its own window | **important** | Native expectation (Messages, Telegram, Slack); persist via `NSWindow` state restoration. |
| Separate search window | **nice** | |

## 2.4 Menu-bar quick reply

| Feature | Priority | Notes |
|---|---|---|
| `NSStatusItem` popover: unread threads + inline reply, hotkey-dismiss | **important** | Open market — no mainstream messenger nails this. Strong differentiator. |
| Menu-bar unread count badge | **important** | |

Ref: [Raycast menu-bar commands](https://www.raycast.com/changelog/page/9)

## 2.5 Rich notifications with inline reply

| Feature | Priority | Notes |
|---|---|---|
| `UNNotificationAction` text-input reply from banner / Notification Center | **core** | Reply without opening the app (macOS Messages model). |
| Quick-react actions in notification | **nice** | Tapback-style reactions as notification buttons. |
| Per-thread notification customization (sound, preview on/off) | **important** | Ties to §1.7 chat-specific sounds. |

Ref: [Apple — Messages notifications](https://support.apple.com/guide/messages/mute-and-manage-notifications-icht3a134ea1/mac) · [Apple — Tapbacks](https://support.apple.com/guide/messages/send-tapbacks-icht504f698a/mac)

## 2.6 Full-text local search across all history

| Feature | Priority | Notes |
|---|---|---|
| On-device index of all messages (SQLite FTS5 / Core Spotlight) | **core** | Messenger is notably weak here. Local-first like Texts.com. |
| Search by sender, date, media-type, thread | **important** | Faceted search. |
| System-wide Spotlight indexing of messages/contacts | **nice** | Core Spotlight donation. |

Refs: [Texts FAQ (on-device)](https://texts.com/faq) · [Texts review](https://www.toolify.ai/tool/texts-com)

## 2.7 Local history export / backup

| Feature | Priority | Notes |
|---|---|---|
| Export thread / all history (JSON + attachments) | **important** | Market gap; pairs with local-first DB. Privacy + ownership selling point. |
| Queryable local archive DB | **nice** | |

Ref: [Texts FAQ](https://texts.com/faq)

## 2.8 Multi-account

| Feature | Priority | Notes |
|---|---|---|
| Multiple Facebook accounts (personal + page/business) | **important** | With per-account notification + Focus rules. |
| Instagram DM inbox alongside Messenger | **important** | messagix bridges both; unify the inbox. |

Refs: [Beeper](https://www.beeper.com/) · [Texts](https://texts.com/faq) · [mautrix/meta](https://github.com/mautrix/meta)

## 2.9 Markdown / rich-text composer

| Feature | Priority | Notes |
|---|---|---|
| Inline markdown (bold/italic/strike/code/code-block) | **important** | Telegram/Slack/Discord do it; Messenger composer is plain. Note: rendering depends on what the wire protocol actually transmits — Messenger may flatten formatting, so this may be local-display + plain-text-on-send. |
| Live-preview composer | **nice** | |

## 2.10 Link previews / unfurling

| Feature | Priority | Notes |
|---|---|---|
| Native, cached, privacy-respecting unfurl (title/thumb/desc) | **important** | Fetch previews locally, not via a tracking proxy. Toggle on/off. |

## 2.11 Drag-and-drop + Quick Look

| Feature | Priority | Notes |
|---|---|---|
| Drag files/images from Finder into composer; paste from clipboard | **core** | Native baseline. |
| Drag received media out to Finder/Desktop | **important** | |
| Quick Look (Space) on attachments | **important** | Native affordance Electron fakes poorly. |

## 2.12 Focus / DND integration (macOS Focus filters)

| Feature | Priority | Notes |
|---|---|---|
| Focus Filter via App Intents (per-Focus thread allowlist) | **important** | Almost no third-party messenger does this — pure native differentiation. |
| Share Focus status / breakthrough for VIPs | **nice** | Messages model. |

Refs: [Intego — Focus filters](https://www.intego.com/mac-security-blog/how-to-use-focus-to-limit-notifications-in-ios-15-and-macos-monterey/) · [Apple — Messages notifications](https://support.apple.com/guide/messages/mute-and-manage-notifications-icht3a134ea1/mac)

## 2.13 Snooze / remind-me

| Feature | Priority | Notes |
|---|---|---|
| Snooze thread out of inbox until time | **important** | Beeper/Things/Superhuman pattern; natural-time presets in the palette. |
| "Remind me about this message" | **nice** | |

Refs: [Beeper](https://www.beeper.com/) · [Texts review](https://www.toolify.ai/tool/texts-com)

## 2.14 Scheduled send

| Feature | Priority | Notes |
|---|---|---|
| Hold-Send → schedule, editable queue | **important** | Telegram gold standard; Texts "Send Later." (Also Part 1 §1.1.) |

Refs: [Telegram scheduled messages](https://telegram.org/blog/scheduled-reminders-themes) · [Texts review](https://www.toolify.ai/tool/texts-com)

## 2.15 Message translation

| Feature | Priority | Notes |
|---|---|---|
| On-device translation (Apple Translation framework), per-message + whole-thread | **important** | Private/offline; Telegram-Premium-grade without the cloud. |

Refs: [Telegram chat translation](https://createbytes.com/insights/telegram-ui-ux-review-design-analysis) · [Texts review](https://www.toolify.ai/tool/texts-com)

## 2.16 Spotlight / Shortcuts / system integration

| Feature | Priority | Notes |
|---|---|---|
| App Intents: "Message [person] on Relay" in Spotlight (macOS 26 actions + Quick Keys) | **nice** | |
| Shortcuts actions (send, unread count, snooze) + URL scheme | **nice** | Things 3 model. |
| Handoff / Continuity (if an iOS companion ships) | **nice** | `NSUserActivity` thread handoff. |

Refs: [Apple — Spotlight actions](https://support.apple.com/guide/mac-help/take-actions-and-shortcuts-in-spotlight-mchl4953dfeb/mac) · [9to5Mac — Spotlight 26](https://9to5mac.com/2025/06/10/macos-26-spotlight-gets-actions-clipboard-manager-custom-shortcuts/) · [Things 3.17 Shortcuts](https://www.macstories.net/reviews/things-3-17-overhauls-the-apps-shortcuts-actions/)

## 2.17 Native polish (table stakes for "premium")

| Feature | Priority | Notes |
|---|---|---|
| Vibrancy/materials, true dark mode, accent tinting | **important** | Things/Raycast design bar. |
| Window state restoration (selected thread, scroll pos, tear-offs) | **important** | |
| WidgetKit widgets (unread count / recent threads) | **nice** | |
| Canned replies / snippets | **nice** | Raycast snippets model. |

Refs: [Texts review (dark mode/UI)](https://www.toolify.ai/tool/texts-com) · [Raycast](https://www.raycast.com/changelog/page/9)

### Highest-ROI steal list (Part 2)
1. `⌘K` switcher + verb palette · 2. Full keyboard nav incl. *navigate-without-marking-read* · 3. **Focus Filter** App Intent · 4. Local FTS search + export · 5. Inline-reply notifications + **menu-bar quick-reply popover** · 6. Scheduled send + snooze · 7. On-device translation · 8. Native polish (vibrancy, restoration, Quick Look, Handoff, Shortcuts, widgets).

---

# PART 3 — The hard question: VOICE & VIDEO CALLS

## Verdict

> **Full calling is out of reach. No reverse-engineered Messenger client or bridge has *ever* implemented placing/answering voice or video calls. There is a real but limited partial path: you can DETECT and DISPLAY incoming/missed calls via the same MQTT stream you already parse — you just can't ring-and-answer with live media.**

Treat "answer/place calls in Relay" as **out of scope**. Ship call *awareness* + an "open in official app" fallback.

## Evidence by project

- **mautrix-meta** (current, active; same author as your likely backend): its ROADMAP lists messages/reactions/edits/presence/typing/membership and **zero** call/VoIP/RTC entries. The `messagix` `socket` task package has only messaging/thread/contact/group task types — **no AVCall/RTC task** exists. → [ROADMAP](https://github.com/mautrix/meta/blob/main/ROADMAP.md) · [messagix socket tasks](https://pkg.go.dev/go.mau.fi/mautrix-meta/messagix/socket)
- **mautrix-facebook** (deprecated predecessor): in v0.5.0 (2023) added exactly one call feature — *"notice message when a call is received."* **Notification only**; cannot place/answer. → [CHANGELOG](https://github.com/mautrix/facebook/blob/master/CHANGELOG.md)
- **Beeper** (Automattic; uses mautrix bridges): explicitly lists *"Facebook video/audio calls"* as **unsupported**; tells users to open the native app. → [Beeper Messenger help](https://help.beeper.com/en_US/chat-networks/messenger) · [Beeper FAQ](https://www.beeper.com/faq)
- **Texts.com** (Automattic, merging into Beeper): text-first; routes calls/native-only features to native apps. No Messenger calling. → [TechCrunch — Automattic/Beeper](https://techcrunch.com/2024/04/09/wordpress-com-owner-automattic-acquires-multi-service-messaging-app-beeper-for-125m/)
- **fbchat** (archived Python lib): browser-imitation; never enumerated call events; no calling. → [fbchat](https://github.com/fbchat-dev/fbchat)

**No public project has ever placed or answered a Messenger call programmatically.**

## Why — the technical wall

A Messenger call has two layers:

1. **Media (WebRTC — the "easy" part):** built on Google's `webrtc.org` library (Meta long ran a heavy fork, now modernized to track stable Chromium WebRTC). Codecs are increasingly **proprietary**: audio moved to **MLow** (Meta's low-bitrate codec, fully launched on Messenger/Instagram) plus historical iSAC; video VP8 + AV1/HD. Encryption is **SDES** between mobile clients (keys in signaling), DTLS to browsers. → [Meta — escaping the WebRTC fork (2026)](https://engineering.fb.com/2026/04/09/developer-tools/escaping-the-fork-how-meta-modernized-webrtc-across-50-use-cases/) · [MLow codec](https://engineering.fb.com/2024/06/13/web/mlow-metas-low-bitrate-audio-codec/) · [webrtcHacks teardown](https://webrtchacks.com/facebook-webrtc/)
2. **Signaling (proprietary — the real wall):** runs over **MQTT** (same broker as messages), using **Rsys** — Meta's unified, proprietary state-machine signaling stack for P2P + group calls. Undocumented, frequently changed, tied to client integrity/attestation. To place/answer a call you'd have to reverse-engineer Rsys offer/answer/ICE/SDP semantics over MQTT, negotiate MLow, and reproduce SDES key exchange. → [Meta — Rsys](https://engineering.fb.com/2020/12/21/video-engineering/rsys/) · [Meta WebRTC modernization](https://engineering.fb.com/2026/04/09/developer-tools/escaping-the-fork-how-meta-modernized-webrtc-across-50-use-cases/)

The signaling wall has gotten **higher** since the last public teardown (Rsys 2020, WebRTC modernization 2026 are Meta confirming the stack only became more unified and proprietary).

## The partial path (build this)

- Call ring/state events flow over the **same MQTT stream** you already parse for messages. → [webrtcHacks](https://webrtchacks.com/facebook-webrtc/)
- mautrix-facebook proved a **"call received" notice** is observable. → [CHANGELOG](https://github.com/mautrix/facebook/blob/master/CHANGELOG.md)
- Multi-device ringing means an unanswered incoming call rings all logged-in devices, so a passive client on the account can observe the ring. → [webrtcHacks](https://webrtchacks.com/facebook-webrtc/)

**So Relay can realistically:** show a native incoming-call banner ("X is calling…"), log missed/completed calls in the thread, and offer **"Answer in Messenger app"** as a deep-link fallback. Expect parsing churn as Meta changes payloads. **Don't** attempt live media.

---

## Appendix — Cross-cutting build risks (priority-ranked)

1. **[core] E2EE-by-default** (Part 1 §1.6) — biggest risk; without Meta's E2EE/Secure-Storage implementation Relay may not read/send normal DMs at all. Gate the whole project on tracking mautrix-meta's E2EE progress.
2. **[core] Auth without messenger.com** — the standalone web client is dead (April 2026) and phone-only desktop sign-in is gone; ensure your login flow uses a path messagix still supports (Facebook-account login).
3. **[important] Protocol churn** — Meta changes payloads; budget ongoing maintenance, especially for call-event parsing and any formatting/theme rendering.
4. **[skip] Calls** — accept the verdict; ship awareness + fallback only.

---

### Master source list
[Messenger features](https://www.messenger.com/features/) · [IBTimes — desktop/messenger.com shutdown 2026](https://www.ibtimes.com.au/facebook-messenger-desktop-update-2026-5-key-things-users-must-know-after-messengercom-shutdown-1866704) · [SocialBee — 2026 Meta updates](https://socialbee.com/blog/facebook-updates/) · [iDropNews — Messenger upgrades](https://www.idropnews.com/news/facebook-messenger-is-getting-some-huge-upgrades/203732/) · [Unsend in Messenger 2026](https://ucompares.com/social-media/messenger/unsending-messages-in-messenger/) · [Undo a reaction](https://www.socialappshq.com/facebook/how-to-undo-and-delete-a-reaction-on-messenger/) · [TechWiser — tips/effects](https://techwiser.com/best-and-new-facebook-messenger-tips-and-tricks/) · [Messenger HD calls/media](https://about.fb.com/news/2024/11/introducing-ai-backgrounds-noise-suppression-and-more-messenger-calling/) · [Cyberly — default E2EE](https://www.cyberly.org/news/facebook-messenger-rolls-out-default-end-to-end-encryption-what-it-means-for-your-privacy/) · [ExpressVPN — Secret Conversations replaced](https://www.expressvpn.com/blog/secret-conversation-messenger/) · [Messenger Help — restore E2EE](https://www.facebook.com/help/messenger-app/431055522328649) · [Broadcast channels (TechTimes)](https://www.techtimes.com/articles/297719/20231018/metas-broadcast-channels-expand-facebook-messenger.htm) · [Broadcast channels 2026 (Izoate)](https://www.izoate.com/blog/facebook-broadcast-channels-2026-the-ultimate-guide-for-creators-brands/) · [Birdeye — Messenger icons](https://birdeye.com/blog/facebook-messenger-icons-and-symbols/) · [Active status](https://stripe.jhu.edu/news/why-does-active-status-disappear-on-messenger) · [Read receipts](https://beebom.com/how-turn-off-read-receipts-instagram/) · **mautrix/Beeper/RTC:** [mautrix/meta](https://github.com/mautrix/meta) · [ROADMAP](https://github.com/mautrix/meta/blob/main/ROADMAP.md) · [messagix socket tasks](https://pkg.go.dev/go.mau.fi/mautrix-meta/messagix/socket) · [mautrix-facebook CHANGELOG](https://github.com/mautrix/facebook/blob/master/CHANGELOG.md) · [mautrix/meta E2EE #7](https://github.com/mautrix/meta/issues/7) · [Beeper Messenger help](https://help.beeper.com/en_US/chat-networks/messenger) · [Beeper FAQ](https://www.beeper.com/faq) · [fbchat](https://github.com/fbchat-dev/fbchat) · [Meta — escaping WebRTC fork 2026](https://engineering.fb.com/2026/04/09/developer-tools/escaping-the-fork-how-meta-modernized-webrtc-across-50-use-cases/) · [Meta — Rsys](https://engineering.fb.com/2020/12/21/video-engineering/rsys/) · [MLow codec](https://engineering.fb.com/2024/06/13/web/mlow-metas-low-bitrate-audio-codec/) · [webrtcHacks — FB WebRTC](https://webrtchacks.com/facebook-webrtc/) · **Native-Mac:** [Beeper shortcuts](https://blog.beeper.com/2023/08/17/power-moves-beepers-keyboard-shortcuts/) · [Texts FAQ](https://texts.com/faq) · [Telegram shortcuts](https://blog.invitemember.com/2024-telegram-desktop-shortcuts-effortless-efficiency/) · [Telegram scheduled msgs](https://telegram.org/blog/scheduled-reminders-themes) · [Discord Quick Switcher](https://support.discord.com/hc/en-us/articles/115000070311-Quick-Switcher) · [Slack keyboard nav](https://slack.com/help/articles/115003340723-Navigate-Slack-with-your-keyboard) · [Raycast aliases/hotkeys](https://manual.raycast.com/command-aliases-and-hotkeys) · [Things Quick Entry](https://culturedcode.com/things/support/articles/2249437/) · [Things 3.17 Shortcuts](https://www.macstories.net/reviews/things-3-17-overhauls-the-apps-shortcuts-actions/) · [Apple — Messages notifications](https://support.apple.com/guide/messages/mute-and-manage-notifications-icht3a134ea1/mac) · [Apple — Tapbacks](https://support.apple.com/guide/messages/send-tapbacks-icht504f698a/mac) · [Intego — Focus filters](https://www.intego.com/mac-security-blog/how-to-use-focus-to-limit-notifications-in-ios-15-and-macos-monterey/) · [Apple — Spotlight actions](https://support.apple.com/guide/mac-help/take-actions-and-shortcuts-in-spotlight-mchl4953dfeb/mac) · [9to5Mac — Spotlight 26](https://9to5mac.com/2025/06/10/macos-26-spotlight-gets-actions-clipboard-manager-custom-shortcuts/)
