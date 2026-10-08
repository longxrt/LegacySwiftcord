# Swiftcord on Sequoia — modernization plan

Branch: `sequoia-legacy` (from archived `main`, last upstream code Nov 2023, v0.7.0)
Target: macOS 15 Sequoia (keep deployment target ≥ 14 so modern SwiftUI APIs are available)

## Key finding
The v2 app (macOS 26 only) is closed source, but its networking engine,
**DiscordKit**, is still public and actively updated (last commit 2026-09-07),
and still supports macOS 11+. Legacy Swiftcord pins DiscordKit at 2023-10-13,
77 commits behind. Moving to current DiscordKit gives us v2-era protocol fixes
(tolerant READY decoding, read states, threads, reactions, polls, forwarded
messages, etc.).

- `DiscordKitCore` (latest) builds cleanly with Swift 6.1 on this Mac.
- `DiscordKit` (gateway/UI-helper module) has 3 compile errors upstream
  (it's stale; v2 likely uses only Core). Needs a small local fork:
  - `DiscordGateway.swift:298` — `ReadState.Entry.updatingLastMessage` removed; use `init(id:lastAckedID:)`
  - `GatewayCachedState.swift:105` — `Channel.last_message_id` is now `let`

## Phase 1 — Get it building
- [ ] Install Xcode (blocker), `xcode-select -s`
- [x] Fork DiscordKit locally (`~/Developer/DiscordKit`, branch `sequoia-fork`), fix the 3 errors, point Swiftcord at it as a local package
- [x] Remove duplicate/orphaned package refs in the .xcodeproj, plus the stale "Swiftcord (App Store)" target
      (2× DiscordKit, 2× Lottie, 2× CachedAsyncImage)
- [ ] Fix app-side breakage from DiscordKitCore API changes (unknown until Xcode compiles;
      e.g. readState now uses `ackMessageID` instead of `last_message_id`)
- [x] Clear `DEVELOPMENT_TEAM`, sign "Sign to Run Locally"
- [x] Deployment target raised 12.0 → 14.0
- [x] Change bundle ID (e.g. `io.cryptoalgo.swiftcord.sequoia`) so it doesn't clash with the v2 app

## Phase 2 — Strip dead weight (smaller, faster launch, more private)
- [x] Remove Sentry + AppCenter (telemetry to the original devs' accounts, now unmaintained)
- [x] Remove Sparkle auto-updates (feed points at upstream; would fight our build)
- [ ] Replace SwiftUI-Introspect 0.x hacks with native APIs where possible
- [ ] Re-evaluate Lottie (only used for typing indicator / few animations)

## Phase 3 — Performance
Biggest wins, in order:
1. **Whole-app re-renders on every gateway event.** 18 views observe the entire
   `DiscordGateway` `ObservableObject`. Every presence/typing/read-state update in any
   server re-renders all of them, including the message list. Fix: split into narrow
   observable stores (`@Observable`, macOS 14+) so views only track what they read.
2. **Typing re-renders the message list.** `MessagesViewModel` holds the draft text
   (`newMessage`) next to `messages`, so every keystroke invalidates the history.
   Move composer state into its own model.
3. **O(n²) reply lookup.** Each cell linearly searches `messages` for its quoted
   message. Keep an id→index dictionary.
4. **Flipped-list hack.** History is a `List` rotated 180° via introspection + scale
   effects. Replace with `ScrollView` + `LazyVStack` + `.defaultScrollAnchor(.bottom)`
   and `.scrollPosition` (macOS 14+).
5. **Images decoded full-size on the main thread** (`CachedAsyncImage`). Replace with
   an ImageIO downsampling loader + memory/disk cache sized to the view.
6. **Unbounded message arrays.** Trim history when scrolled far away.

## Phase 4 — Polish (optional)
- Bring over DiscordKit features v2 has: reactions, threads, polls, forwards, pins
- Sequoia-native styling touches (materials, inspector, etc.)

## Note
Swiftcord logs in with a user token (client modification), which is against
Discord's ToS. Same risk as using the official Swiftcord builds.
