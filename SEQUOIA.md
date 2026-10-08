# Swiftcord Sequoia Edition

A maintained fork of **legacy Swiftcord**, the open-source native SwiftUI Discord client for macOS,
updated to run well on **macOS 14 Sonoma and macOS 15 Sequoia**.

The official Swiftcord v2 requires macOS 26 Tahoe and isn't open source. This branch starts from
the archived legacy codebase (v0.7.0, last updated November 2023) and modernizes it: it builds
against today's Discord API library, fixes what broke, and is optimized for speed, battery life and
privacy.

> **Branch:** `sequoia-legacy` · **Based on:** upstream `main` (legacy) · **License:** GPL-3.0, same as upstream

---

## At a glance

| | Legacy Swiftcord | This branch |
|---|---|---|
| Discord library (DiscordKit) | October 2023 | September 2026 (+77 upstream commits, plus fixes) |
| Builds with Xcode 16 / macOS 15 SDK | No | Yes |
| Server channels | Often fail with "Missing Access" | Load reliably |
| Clicking avatars or buttons in messages | Broken on macOS 15 | Works |
| Analytics and crash reporting | Sentry (always on in release) + AppCenter | None |
| Discord tracking on the login page | Runs | Blocked |
| Animated GIF timer | Runs for the whole session at display refresh rate, even when hidden | Only while an animation is visible |
| UI redraws from other users' status changes | Every event, all views | Batched: once/s, 5 s in background, 60 s when hidden |
| OLED Black theme | No | Yes |
| Activity status (games, Apple Music, Spotify, Cider) | No | Yes, opt-in |
| Full user profiles | No | Yes |

Measured on a Release build after startup, idle on an Apple Silicon Mac: **about 0–2 % CPU,
roughly one wakeup every two seconds, about 130 MB of memory.** These are single measurements,
not a formal benchmark against legacy.

---

## Where it's optimized

### Responsiveness

- **No more whole-window redraws on every Discord event.** Every view observes the shared gateway
  object, and legacy sent a change notification after *every* incoming event, while each presence
  update (someone going online/idle/offline) triggered another. In busy servers that's a constant
  stream. Changes are now coalesced: cache changes are merged into one update per run-loop turn,
  and other users' presence changes are batched (see *Battery* below).
  *(`DiscordKit`: `DiscordGateway.swift`)*
- **Faster startup.** The initial presence list (often thousands of entries) was inserted one at a
  time into a published dictionary, notifying observers for each. It's now merged in one pass.
- **Typing no longer redraws the chat history.** The draft text lived in the same model as the
  message list, so every keystroke invalidated the whole history. The composer now has its own
  model observed only by the text field. *(`MessagesViewModel.swift`, `MessagesView.swift`)*
- **Cheaper message rendering.** Reply previews used to scan the entire loaded history for each
  reply on every render (quadratic). They now use the replied-to message Discord already sends.
- **Cheaper server list.** Working out which servers sit outside folders was
  servers × folders × folder size on every redraw; it's now a single set lookup.
- **New message list.** The chat history was a `List` rotated 180° in AppKit and flipped back in
  SwiftUI. It's now a lazy, bottom-anchored `ScrollView` that keeps your place when older messages
  load (macOS 15). This also fixed click handling (see *Reliability*).

### Battery and multitasking

- **Removed a permanent refresh-rate timer.** Legacy's GIF library (SwiftyGif) starts a
  `CVDisplayLink` when the first animated image appears and never stops it, waking the app 60–120
  times a second for the rest of the session, even when minimized. Animated images now use
  SDWebImage, which only runs a display link while something is actually playing.
- **Animations pause when nobody can see them.** GIFs, animated avatars, stickers and the typing
  indicator stop when their window is minimized, hidden, on another Space, fully covered, or the
  display is off, and when they scroll out of view. *(`WindowVisibility.swift`)*
- **Background-aware updates.** Other users' presence changes redraw at most once a second while
  Swiftcord is frontmost, every 5 seconds when it's behind other apps, and every 60 seconds when
  it's hidden. Returning to the app applies anything pending immediately.
  *(`AppActivityMonitor.swift`)*
- **Memory pressure handling.** When macOS reports memory pressure, in-memory image caches are
  released (the disk cache is kept).
- **Bounded caches.** Images are cached by SDWebImage with limits (96 MB in memory, 384 MB / 1 week
  on disk), decoded off the main thread. The old URL cache now only holds API responses.
- **Sudden termination.** macOS can quit the app instantly at logout or shutdown.

### Reliability

- **Up-to-date Discord library.** DiscordKit is updated from October 2023 to September 2026,
  including tolerant decoding: one malformed message or channel is skipped instead of failing the
  whole page. A small fork fixes the gateway module for the current core library.
- **Server channels load.** Discord sends hidden channels too; legacy picked a channel before
  computing permissions and often opened one you can't see. Channels are now filtered by your
  permissions, using Discord's rule that role allows win over role denies.
- **New message types don't vanish.** Messages using newer layouts (common with bots) failed to
  decode and were dropped entirely. Unknown component types are now tolerated.
- **Messages and buttons are clickable again.** On macOS 15, clicks inside the old flipped list
  landed at the mirrored position, so avatars and attachments couldn't be clicked.
- **Crash fixes** for empty DM recipient lists (deleted accounts), group-add messages with no
  mentions, the Credits page, and the media player.
- **Messages go to the right channel.** Sending captured the channel when the request ran, so a
  quick channel switch could send to the wrong one.
- **Your typing indicator works.** Legacy compared the new draft with itself, so "is typing…" was
  never sent.
- **Unread markers** read Discord's current read-state field.

### Privacy

- **Removed** Sentry crash reporting (enabled in every release build regardless of settings),
  AppCenter analytics, and the Sparkle updater (which pointed at the upstream feed).
- **Login page tracking blocked.** Login uses Discord's own web page, which runs Discord's
  analytics. A content-blocking rule list now blocks `/science`, `/metrics`, `/track`, Discord's
  Sentry relay and `sentry.io` before the page loads. Login, two-factor, QR login and captcha are
  unaffected.
- The client itself never calls Discord's analytics endpoints. It still sends Discord's standard
  client-identity header, as every official client does; removing it is a known way to get
  accounts flagged.

---

## New features

- **OLED Black theme** (Settings → App → Appearance): pure black backgrounds throughout, with
  near-black surfaces for raised elements.
- **Activity Status** (Settings → App → Activity Status, off by default): show the game you're
  playing and the music you're listening to on your profile.
  - Games are detected when apps launch or quit, from their app category or Discord's list of
    detectable games. No polling.
  - Apple Music and Spotify via their system notifications (no polling, no permissions).
  - Cider via its local RPC API, checked only while Cider is running. Optional API token stored in
    the Keychain.
- **Full user profiles**: "View Full Profile" from any profile card shows the banner, badges,
  pronouns, About Me, roles, connected accounts, a private note, and mutual servers and friends.

---

## Building

Requires macOS 14 or later and Xcode 16. The project expects the DiscordKit fork in a folder next
to this repository:

```bash
git clone -b sequoia-legacy https://github.com/longxrt/Swiftcord.git Swiftcord
git clone -b sequoia-fork https://github.com/longxrt/DiscordKit.git DiscordKit
```

The DiscordKit fork is currently a private repository, so these steps only work for its owner.

Then open `Swiftcord/Swiftcord.xcodeproj`, or build and install to `/Applications` with:

```bash
Swiftcord/Scripts/install.sh
```

To package a universal (Apple Silicon + Intel) DMG for distribution in `dist/`:

```bash
Swiftcord/Scripts/make-dmg.sh
```

Builds are signed to run locally ("Sign to Run Locally") with their own bundle ID
(`io.cryptoalgo.swiftcord.sequoia`), so they don't conflict with the official app.

---

## Notes

- Swiftcord logs in with your user account, which Discord's Terms of Service don't permit for
  third-party clients. The risk is the same as with any official Swiftcord build.
- All credit for Swiftcord goes to the original Swiftcord contributors. This branch isn't
  affiliated with or endorsed by the Swiftcord project.
- Detailed progress notes are in [`SEQUOIA_PLAN.md`](SEQUOIA_PLAN.md).
