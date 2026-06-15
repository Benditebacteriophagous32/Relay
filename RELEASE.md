# Signing & releasing Relay

Relay is distributed like most open-source Mac apps: **ad-hoc signed, not notarized,
tied to no Apple Developer account.** Users approve it once on first launch (System
Settings → Privacy & Security → "Open Anyway"). No paid membership, certificates, or
notarization needed. Auto-update still works — Sparkle verifies its own EdDSA signature
on the appcast, independent of Apple.

## Run locally
```bash
scripts/run-native.sh
```
Builds the universal Go helper + app, signs locally, installs to `/Applications`, runs.

## Cut a release
```bash
scripts/release.sh
```
Builds the universal (Intel + Apple Silicon) helper + app, **ad-hoc signs** it, and
produces:
- `dist/Relay.dmg` — the drag-to-Applications download for the Releases page
- `dist/Relay.zip` — the Sparkle update artifact
- `dist/appcast.xml` — the EdDSA-signed update feed

It prints the exact `gh release create` command, e.g.:
```bash
gh release create v1.0 dist/Relay.dmg dist/Relay.zip dist/appcast.xml \
  --title "Relay v1.0" --notes "…"
```
The tag **must** be `v<MARKETING_VERSION>` so the appcast's download URLs resolve.
Bump `MARKETING_VERSION` **and** `CURRENT_PROJECT_VERSION` in `project.yml` before each
release (Sparkle compares `CURRENT_PROJECT_VERSION` to decide what's newer).

## Auto-update (Sparkle)

Wiring is done: the Sparkle SPM dependency plus `SUFeedURL`/`SUPublicEDKey` in the
generated `Info.plist`, pointing at `releases/latest/download/appcast.xml`. Updates are
**manual** — the user clicks "Download the Latest Version" (Settings) or "Check for
Updates…" (menu); there are no background checks.

The EdDSA signing keypair was made once with Sparkle's `generate_keys` (private key in
your login Keychain; public key is `SUPublicEDKey` in `project.yml`). `release.sh` signs
the appcast with `generate_appcast`, looking for the Sparkle CLI tools in `.sparkle-tools/`
(git-ignored) or the resolved SPM artifacts. To (re)fetch the tools:
```bash
TAG=$(gh release view --repo sparkle-project/Sparkle --json tagName -q .tagName)
mkdir -p .sparkle-tools && cd .sparkle-tools
curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$TAG/Sparkle-$TAG.tar.xz" | tar -xJ
```

## Notes
- The project is **ad-hoc signed** (`CODE_SIGN_IDENTITY "-"`, no team). To run from Xcode
  with your own account instead, set `CODE_SIGN_STYLE: Automatic` + your team in `project.yml`.
- Entitlements (`RelayNative/RelayNative.entitlements`) cover hardened-runtime JIT +
  microphone; the app is not sandboxed (direct distribution only).
- Want warning-free installs later? You can add a paid Developer ID + notarization step
  on top of this without changing anything else.
