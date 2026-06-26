# MultiClip

A macOS menu-bar app for peer-to-peer clipboard sharing across Macs on the same
local network. No server, no account — devices that share a secret key discover
each other over Bonjour and offer their copies to one another.

## How it works

- **Peer-to-peer.** Every instance both advertises and browses a Bonjour service
  (`_multiclip._tcp`). There is no central server. To avoid a dual-connection
  race, the peer with the lexicographically smaller device id dials out; the
  other accepts — exactly one encrypted channel per pair.
- **Encrypted & key-gated.** All traffic is AES-GCM encrypted with a key derived
  (HKDF-SHA256) from a shared secret you set. A device with the wrong/empty key
  cannot decrypt a single frame, so it simply can't join.
- **Copy → announce.** When you copy on any device, only *metadata* (a preview,
  size, file list) is broadcast to peers. The bytes stay put.
- **Never auto-pastes.** Incoming items appear in the menu under "From Other
  Devices". MultiClip never writes to a remote clipboard automatically — you pick
  an item, and only then are its bytes fetched and placed on *your* clipboard.
- **Lazy transfer.** Payloads (including files up to the size limit) transfer
  on-demand when you select an item. File transfers raise a completion
  notification; plain clipboard syncs stay silent.
- **History.** The last N local copies (default 5, configurable up to 50) are
  kept and persist across restarts.
- **Hot key.** A configurable global hot key (default ⌘⌥V) fetches the most
  recent remote item and pastes it into the frontmost app.

Supported content: plain text, rich text (RTF), images, and files.

## Build & run

Requires Xcode 15+ (built/tested with Xcode 26, Swift 6.3) on macOS 13+.

```sh
./build_app.sh          # release build → build/MultiClip.app (ad-hoc signed)
open build/MultiClip.app
```

For a quick development build:

```sh
swift build             # debug binary at .build/debug/MultiClip
```

### Signed, notarized release (DMG)

Produces a Developer ID–signed, notarized, stapled `dist/MultiClip-<version>.dmg`.

One-time setup of a notarization profile (uses an App Store Connect API key):

```sh
xcrun notarytool store-credentials multiclip-notary \
  --key AuthKey_XXXXXXXX.p8 --key-id XXXXXXXX --issuer <issuer-uuid>
```

Then:

```sh
./release.sh
```

The signing identity and profile name can be overridden with the `SIGN_IDENTITY`
and `NOTARY_PROFILE` environment variables. Releases are published to GitHub via
`gh release create`.

## First run

1. Launch the app — a clipboard icon appears in the menu bar (no Dock icon).
2. The Settings window opens automatically. Enter a **Shared key** (the same
   string on every device you want to link) and a device name.
3. macOS will prompt for **Local Network** access — allow it so peers can be
   discovered.
4. For the paste hot key, grant **Accessibility** permission when prompted
   (System Settings ▸ Privacy & Security ▸ Accessibility).

## Permissions used

| Permission | Why |
|------------|-----|
| Local Network | Bonjour discovery + peer connections |
| Accessibility | Synthesizing ⌘V for the paste hot key |
| Notifications | "Files received" completion notices |
| Keychain | Storing the shared key |

## Tests

```sh
swift build && .build/debug/MultiClip --selftest      # crypto + framing + loopback transport
```

Two-instance end-to-end check over real Bonjour (distinct ids, same key):

```sh
BIN=.build/debug/MultiClip
MULTICLIP_DEVICE_ID=alpha MULTICLIP_SHARED_KEY=k MULTICLIP_DEVICE_NAME=Alpha $BIN --integration &
MULTICLIP_DEVICE_ID=bravo MULTICLIP_SHARED_KEY=k MULTICLIP_DEVICE_NAME=Bravo $BIN --integration &
```

Each prints `RESULT: SUCCESS` after fetching the other's payload.

## Project layout

```
Sources/MultiClip/
  main.swift                 Entry point (+ --selftest / --integration modes)
  AppDelegate.swift          Wires everything together
  Models/                    ClipboardItem, Preferences
  Clipboard/                 Pasteboard read/write + change monitor
  Storage/                   History persistence, Keychain, paths
  Net/                       Crypto, wire protocol, SecureChannel, PeerManager
  System/                    Global hot key, paster, notifications, keycodes
  UI/                        Status-bar menu, settings window, icon
Resources/Info.plist         Bundle metadata (LSUIElement, Bonjour, Local Network)
build_app.sh                 Assembles + ad-hoc signs MultiClip.app
```

## Notes & limitations

- Same-subnet LAN only (by design — Bonjour/mDNS).
- Ad-hoc signed. For distribution to other Macs without Gatekeeper friction,
  sign and notarize with an Apple Developer ID.
- Remote items remain listed after a peer disconnects; selecting one then fails
  gracefully (a beep / failed-transfer notice).
