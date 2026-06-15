# Relay — Build Roadmap

The actionable plan. Pairs with [FEATURE_INVENTORY.md](FEATURE_INVENTORY.md) (the full
feature catalog + sources) and is grounded in a **ground-truth audit of what the two
protocols actually expose** — so every "feasible" item below names the exact Go task/
function to call. Nothing here is aspirational hand-waving.

Two protocols back Relay:
- **Lightspeed** (`messagix`, the non-E2EE MQTT path) — group chats, threads, presence.
- **whatsmeow** (the E2EE path) — **now the primary path**, because Meta made E2EE the
  **default** for all personal 1:1 chats in 2026. The official Messenger desktop app was
  killed (Dec 2025) and `messenger.com` was shut down (Apr 2026), so Relay isn't chasing
  a first-party app — it's filling a vacuum.

---

## 0. Where we are (already shipped — slices 1–10)

✅ 1:1 + group text messaging (both protocols)  ✅ media send/receive (image/video/audio/file, both protocols)
✅ reactions (add/remove, both)  ✅ reply / forward / copy  ✅ unsend & delete sync (both)
✅ delivered/read receipts  ✅ typing indicator  ✅ presence (partial — push-on-change only)
✅ voice-note recording  ✅ notifications + dock badge  ✅ history backfill (partial — limited by what Meta stores for E2EE)
✅ Liquid Glass reaction picker, Esc-to-empty, paste-to-send  ✅ **new app icon + old WebKit wrapper deleted**

**Reconciliation vs. the research:** the feature catalog flags "E2EE-by-default" as the #1
unbuilt risk. For Relay it's **largely mitigated** — whatsmeow already carries our E2EE text/
media/reactions/unsend today. The remaining E2EE gap is **Secure-Storage history restore**
(see §6), not basic send/receive.

---

## 1. Feasibility key

Each feature is tagged with the protocol surface that backs it (from the audit):

- **`LS:<Task>`** — a real `messagix` socket task or `LS*` table op exists (Lightspeed).
- **`WM:<fn>`** — a real whatsmeow function/event exists (E2EE path).
- **`local`** — pure client-side; no protocol dependency.
- **`✗`** — no protocol support anywhere; do not attempt.

Priority: **core** (broken without it) · **important** (heavy-user expectation) · **nice** (delight) · **skip**.

---

## 2. Feature → protocol feasibility matrix

The merge of the two ground-truth audits with the product catalog. This is the part the
catalog alone couldn't give: *exactly what to call.*

### Messaging
| Feature | Pri | Backed by |
|---|---|---|
| Edit sent message (15-min window + "Edited" marker) | important | `LS:EditMessageTask` · `WM:BuildEdit` (20-min cap, `ConsumerApplication_Content_EditMessage`) |
| Mentions (@) in groups | important | `LS:SendMessageTask.MentionData` · `WM:ContextInfo.MentionedJID` |
| Received-reply quote parse (render incoming quotes) | important | `LS:LSInsertMessage.ReplyMessageText` *(already a pending fix)* |
| Silent / no-notification send | nice | `LS:SendMessageTask` flag |
| Drafts (per-thread, persistent) | important | `local` |

### Stickers / GIFs
| Sticker send | important | `LS:SendMessageTask.StickerId` · `WM:ConsumerApplication_StickerMessage` |
| GIF search + send (Giphy/Tenor) | important | `LS:SendMessageTask.Url + AttributionAppId` (EXTERNAL_MEDIA) |

### Inbox / organization
| Message requests folder | core | `LS:FetchThreadsTask` (MessagingTag) + `LS:LSDeleteThenInsertMessageRequest` (approve/ignore) |
| Spam folder | important | `LS:FolderType=SPAM` |
| Archive / un-archive | core | `LS:LSMoveThreadToArchivedFolder` / `LSMoveThreadToInboxAndUpdateParent` |
| Mute (timed/forever) | core | `LS:MuteThreadTask` (expire=0 to unmute) |
| Mark read / unread | core | `LS:ThreadMarkReadTask` (read ✓) · **mark-unread has no task — do locally** |
| Pin chat to top | important | `LS` thread folder/sort fields |
| Pin message in thread | nice | `LS:LSSetPinnedMessage` / `LSClearPinnedMessages` |
| Block / unblock | important | **`✗` not in messagix socket — GraphQL only** (separate call needed) |
| Delete thread | important | `LS:DeleteThreadTask` |

### Search
| In-thread search | core | `LS` message search (`LSInsertSearchResult`) + **`local` FTS index** |
| Global search (people + messages) | core | `LS:SearchUserTask` + **`local` SQLite FTS5** |

### Groups
| Add / remove member | core | `LS:AddParticipantsTask` / `RemoveParticipantTask` · `WM:UpdateGroupParticipants` |
| Rename / set photo | core | `LS:RenameThreadTask` / `SetThreadImageTask` · `WM:SetGroupName`/`SetGroupPhoto` |
| Admin promote/demote | important | `LS:UpdateAdminTask` · `WM:UpdateGroupParticipants(Promote/Demote)` |
| Invite link | important | `WM:GetGroupInviteLink` / `JoinGroupWithLink` |
| Nicknames (per-member) | important | `LS:LSAddParticipantIdToGroupThread.Nickname` |
| Approval mode / join requests | nice | `LS:LSUpdateThreadApprovalMode` · `WM:SetGroupJoinApprovalMode` |
| Leave group | core | `LS:RemoveParticipantTask`(self) |

### Customization
| Chat theme / color (render + set) | important | `LS:LSUpdateThreadTheme` (+ thread `OutgoingBubbleColor`/`ThemeFbid`/`CustomEmoji`) |
| Per-member nickname | important | (see Groups) |

### Calls — **awareness only** (see §5)
| Incoming-call banner | important | `WM:events.CallOffer`/`CallOfferNotice` · `LS` thread `OngoingCallState` |
| Missed/ended call timeline entry | important | `WM:events.CallTerminate`/`CallReject` |
| Reject incoming call | nice | `WM:RejectCall` (the *only* call action that exists) |
| Place / answer with live media | skip | **`✗` Rsys+MLow wall — no project has ever done it** |
| "Open in Messenger app" deep-link fallback | important | `local` |

### Interactive / utility
| Polls (create + vote) | nice | `LS:CreatePollTask`/`UpdatePollTask` · `WM:BuildPollCreation`/`BuildPollVote` |
| Disappearing-message timer | important | `WM:SetDisappearingTimer` · `LS` thread `DisappearingSettingTtl` |
| View-once media (receive) | nice | `WM:ViewOnceMessage` (auto-unwrapped) |
| Starred / saved messages | important | `local` |
| Live / static location (receive) | nice | `WM:LocationMessage`/`LiveLocationMessage` |

### Native-Mac power layer (all `local`)
⌘K switcher · command/verb palette · full keyboard nav incl. *navigate-without-marking-read* ·
menu-bar quick-reply popover · inline-reply notifications · scheduled send · snooze ·
Focus filter (App Intents) · on-device translation (Apple Translation) · drag-drop + Quick Look ·
link-preview unfurl · multi-window / tear-off · local history export · markdown composer ·
app lock (biometrics) · widgets · Shortcuts/App Intents.

---

## 3. Infra prerequisite (do early — unblocks search, export, durability)

**Migrate persistence from the JSON cache to a local SQLite store (FTS5).**
The hard never-delete constraint, global full-text search, and history export all converge on
one foundation. The current single-JSON cache won't scale to full-history FTS and risks the very
data-loss the user forbade. A WAL-mode SQLite DB (messages, threads, contacts, attachments,
reactions, receipts) with an FTS5 virtual table is the right base. **This is the single highest-
leverage infra move** — schedule it before the search/export milestones.

---

## 4. Sequenced milestones

Ordered by (daily value × confirmed feasibility). Each milestone is a shippable slice.

**✅ Infra (§3) — DONE 2026-06-14.** Messages migrated from the JSON cache to SQLite (WAL) with an
FTS5 index (`RelayNative/MessageStore.swift`). 217 msgs migrated, backup at `cache.premigration.bak`.
`db.search()` is wired and ready for M2.

**◑ M1 — Inbox that feels real** *(core)* — **mostly DONE 2026-06-14**
DONE: requests + spam + archived folder **sections** · mute/unmute (synced) · pin (local) ·
mark read/unread · delete thread (synced) · thread context menu · `⌘K` quick switcher.
DEFERRED (no socket task — GraphQL-only): archive-*from-Relay* button, message-request approve/ignore
button (replying accepts it), block/unblock. We render these folders, just can't trigger the action yet.

**✅ M2 — Search — DONE 2026-06-14**
Search bar in the sidebar over the FTS index: conversation-name matches + full-text message search
across all history, with jump-to-message (opens the thread and scrolls to the hit). Local-first/instant.
Still open (later): faceted filters (sender/date/media-type), in-composer ⌘F within a thread.

**✅ Auth (was M7's biggest item) — DONE 2026-06-14**
Session moved to the **Keychain** (auto-migrated from the old Desktop file) + an **in-app Facebook web
login** so re-auth never needs the deleted web app again. Drops to the login screen on `needLogin`.
Remaining M7: app lock (biometrics), full Liquid Glass design pass, settings window.

**◑ M3 — Message-level parity** *(important)* — **core done 2026-06-14**
DONE: edit sent message (both protocols, send+receive, "edited" marker) · received-reply quote
rendering (both protocols) · drafts (per-thread, persistent).
STILL OPEN (M3b): group @-mentions · pin message (`LSSetPinnedMessage`) · stickers + GIF search.

**✅ M4 + M4b — Group management — DONE 2026-06-14**
rename · add/remove members · leave · admin promote/demote (+ badges) · **set group photo** (mercury upload →
SetThreadImageTask) · **create new group** (sidebar ✎ → pick contacts + name). Genuinely blocked (no protocol
path): per-member nicknames, invite links (Lightspeed), setting chat themes (receive-only). @-mentions deferred.
Bonus unlocked: the mercury upload also enables non-E2EE image send (small follow-up).

**M5 — Call awareness + presence finish** *(important)*
Incoming-call banner · missed/ended-call timeline entries · reject · "Open in Messenger app"
fallback. Finish last-seen/active-status rendering. **No live media** (accepted wall).

**M6 — Native power layer** *(important/nice)*
Command/verb palette · full keyboard nav · menu-bar quick-reply popover · inline-reply
notifications · scheduled send · snooze · Focus filter · on-device translation · drag-drop +
Quick Look · link previews · multi-window · history export. → the stuff that makes it *better*
than Messenger ever was.

**M7 — Security, auth & polish** *(core/important)*
Retire the cookie file for **Keychain-stored auth** · E2EE Secure-Storage history restore (§6) ·
app lock (biometrics) · full Liquid Glass design pass · settings window · widgets · App Intents.

---

## 5. Calls — the settled verdict

**Live voice/video is out of reach and we are not attempting it.** No reverse-engineered client
or bridge (mautrix-meta, mautrix-facebook, Beeper, Texts, fbchat) has *ever* placed or answered a
Messenger call. The wall is **Rsys** (Meta's proprietary MQTT signaling state-machine) + the
**MLow** codec + SDES key exchange, all undocumented and integrity-gated, and getting *more*
locked down (Meta's own 2026 WebRTC-modernization post confirms further unification).

What we **can** do (and will, in M5): whatsmeow already surfaces `CallOffer`, `CallOfferNotice`,
`CallTerminate`, `CallReject` events over the MQTT stream, and exposes `RejectCall`. So Relay can
ring a native incoming-call banner, log missed/completed calls in the timeline, let you reject,
and deep-link "Answer in Messenger app." Expect parsing churn as Meta changes payloads.

---

## 6. Open risks (priority-ranked)

1. **[core] E2EE Secure-Storage history restore** — basic E2EE send/receive works; pulling
   *prior* history on this device still depends on Meta's Secure Storage (PIN / Apple account /
   recovery key). This is the real remaining E2EE gap, and it caps how far back history backfill
   can ever reach.
2. **[core] Auth without messenger.com** — the standalone web client is dead; the cookie-file
   path still works but is fragile. M7 should move to a Facebook-account login messagix supports,
   stored in Keychain.
3. **[important] Protocol churn** — Meta changes payloads; budget ongoing maintenance, especially
   call-event parsing and theme/format rendering.
4. **[important] Block/unblock & friend ops** — not in the messagix socket layer; need a separate
   GraphQL call if we want them.
5. **[skip] Calls** — accept the verdict; awareness + fallback only.
