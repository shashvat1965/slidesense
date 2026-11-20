# Changelog

All notable changes to SlideSense are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Use macOS HUD** (Settings → General, off by default): slides show Apple's
  own volume and brightness HUD instead of SlideSense's. macOS only draws it for
  real key presses, so slides move in the same 16 steps as the keyboard keys.
  Quick Mute sends the mute key, so the system mute HUD appears too. Needs
  Accessibility; without it the app keeps its own HUD.

## [0.1.3] — 2026-11-03

### Added
- **Automatic updates.** SlideSense checks GitHub releases once a day (and on
  demand from Settings → Startup → *Check Now…*), downloads the archive,
  verifies it against the SHA-256 GitHub publishes, swaps the bundle in and
  relaunches. No Sparkle: it refuses to update a bundle whose signature has no
  team identifier, which an ad-hoc build never has.
- Settings → Startup tab: open at login, automatic update checks, version and a
  manual check.
- Settings → Media tab (was "Extras"), so the media controls are easier to find.

### Changed
- Accessibility is only requested while the media strip is enabled — volume and
  brightness never need it.

### Privacy
- The daily update check is the app's only network request: a GET to the public
  GitHub releases API. Nothing about the machine or the user is sent.

## [0.1.2] — 2026-11-03

### Fixed
- The download was called *"damaged"* by Gatekeeper. Without a bundle signature
  the main executable only carries the linker's ad-hoc signature, which fails
  bundle verification ("code has no resources but signature indicates they must
  be present"), and macOS offers no way past it.
- The build script ad-hoc signs the bundle again (`codesign --sign -`), so the
  app is a valid — if unidentified — signature: Gatekeeper now shows the normal
  "Apple could not verify" prompt with an **Open** / *Open Anyway* path.
- Still no certificate, no Apple Developer account, no notarisation, no network.

## [0.1.1] — 2026-11-02

### Changed
- The 1 Hz refresh timer is gone. Volume and mute now arrive as CoreAudio
  property callbacks, and brightness is read when a finger lands and when the
  menu opens. The app no longer wakes up while the pad is untouched.
  (`AppCoordinator` had a timer behind a README that promised "no polling" —
  that was a fair catch, and the code now matches the claim.)

### Planned
- Magic Mouse top-edge support
- Per-edge actions beyond brightness and volume
- Onboarding tour with a live trackpad map

## [0.1.0] — 2026-11-02

The first public release.

### Added
- Volume on the right trackpad edge and brightness on the left, driven by raw
  `MultitouchSupport` contacts rather than an event tap.
- On-screen display: a real Liquid Glass capsule on macOS 26, a frosted HUD on
  macOS 13–15, with a 1 s auto-hide.
- Haptic tick on every level step, with light/medium/strong strength.
- Precise sliding (quarter steps), plus ⇧⌥ fine control while sliding.
- Quick Mute by double-tapping the top-right corner.
- Media strip along the bottom edge: swipe to skip tracks, double-tap to play or
  pause.
- Cursor freeze, bottom-quarter-only mode, required modifier, swap sides, and a
  vertical-axis flip for trackpads that report it backwards.
- Menu bar item with live volume and brightness readouts and a deliberately
  short menu.
- Four-tab settings window: Edges, Feel, Extras, General.
- Open at login via `SMAppService`.
- `--diagnose` and `--dump-touches` diagnostics.

### Notes
- Volume uses CoreAudio, brightness uses the private `DisplayServices` framework
  with a key-event fallback, media commands are posted as system key events.
- Builds are unsigned; downloaded copies need one right-click → Open.

[Unreleased]: https://github.com/shashvat1965/slidesense/compare/v0.1.3...HEAD
[0.1.3]: https://github.com/shashvat1965/slidesense/releases/tag/v0.1.3
[0.1.2]: https://github.com/shashvat1965/slidesense/releases/tag/v0.1.2
[0.1.1]: https://github.com/shashvat1965/slidesense/releases/tag/v0.1.1
[0.1.0]: https://github.com/shashvat1965/slidesense/releases/tag/v0.1.0
