# Relay — Changelog

All notable changes to Relay, newest first. The current version's bullet list is
shown right inside the in-app update prompt ("A new version is available — would
you like to install it?"), so you can see what's new before updating.

## 1.0.3
- Fixed a stale "ghost" notification that replayed an old message every time the app reconnected.
- Update prompts now show this changelog, so you can see what changed before you install.

## 1.0.2
- Reaction bar no longer runs off the side of the window — it now opens toward the centre of the screen.
- Reaction picker stays put while you choose an emoji instead of flickering shut.
- Fixed the double "send" animation that made one message look like it was sent twice.

## 1.0.1
- Hardened Return-to-send on macOS Ventura so Enter reliably sends a message.
- Hid translation menu items on macOS versions that don't support them, so there are no dead buttons.

## 1.0
- First public release: a native macOS Messenger client over a Go backend that speaks Meta's real protocol.
- Messaging with reactions, replies, edit, unsend, forward, and multi-image media.
- Voice notes, emoji, drag-and-drop, scheduled send, snooze, pin, mute, and saved messages.
- Full-text search across all local history; per-chat accent colours, wallpapers, and nicknames.
- On-device translation (macOS 15+), Touch ID lock, menu-bar companion, and one-click in-app updates.
- Universal binary — runs on both Apple Silicon and Intel, macOS 13 Ventura or later.
