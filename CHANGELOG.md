# Changelog

All notable changes to SlideSense are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Ignore While Typing** (on by default). An edge touch that starts within
  0.5 s of a key press is ignored until the finger lifts, so a palm landing
  mid-sentence can't change brightness or volume. Modifier keys on their own
  don't count, so ⇧⌥ fine control and *Require Modifier* still work.
- **Palm Rejection** (on by default). Contacts too large to be a fingertip are
  ignored, including ones that land small and spread before moving.
  `make dump-touches` now prints each contact's `size` and `major` axis.

### Changed
- **Bottom Quarter Only** is now a start zone and is on by default for new
  installs. A slide must start in the lower quarter of a side band, then can
  travel the full height at normal speed. Before, the whole range was squeezed
  into the bottom quarter. Inside the start zone the side band now takes
  priority over the media strip. If you saved the setting as off, it stays off.
  Switch it on in Settings → Edges.
- While Bottom Quarter Only is on, touching the Quick Mute corner and then
  dragging no longer starts a volume slide. Double-tap to mute still works.

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
