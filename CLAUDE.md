# Multi Clip
MacOS tray application that to allow remote clipboard sharing.

## How it needs to work

1. No client/server model - use multicast/broadcast or whatever appropriate
2. When copying on any device joined, sync it to all other devices currently logged in
3. Support rich text, plain text, images and files up to a defined size
4. Do not copy into remote clipboards, but instead offer it as an option on the tray icon to select
5. Keep a history of the last 5 or more (configurable) copies
6. Properly handle necessary permissions required to manage clipboard and transfer the data
7. Continue running on tray when dialogs are closed
8. Files will show notification once transfer is complete, normal clipboard entries will not show anything
9. Configurable hotkey is available to paste most recent remote clipboard item

## Icon
An icon is available in PNG format. It is currently 512x512px with a transparent background. It comes
in 3 styles:

1. clipboard.png - transparent background with black outline of a clipboard
2. clipboard-black.png - transparent background with a black filled clipboard
3. clipboard-color.png - transparent background with a full color clipboard

Choose accordingly.

## Architecture
- Native Swift/SwiftUI
- Strictly same LAN/network (no cross subnet required)
- All peers are MacOS
- Security will be with a shared key (wrong/no key? ignore/can't join)
  - Shared key stored in the macOS Keychain, entered once via Settings
  - All peer traffic encrypted
- Discovery via Bonjour/mDNS; announcements over UDP multicast
- Default history length = last 5
- Default file size limit = 50M
- History should survive restarts
  - Persisted history keeps text + metadata; file/image payloads held in a capped on-disk cache
- File transfer is lazy/on-demand: peers see name+size+icon, bytes transfer only when an
  item is selected; completion notification fires for the requesting device
- Configurable paste hotkey (default ⌘⌥V) loads the latest remote item and synthesizes ⌘V
  into the frontmost app (requires Accessibility permission)

## Rules

1. Work autonomously
