# omarchy-ncspot-arm

Get Spotify working on **Omarchy running on Apple Silicon Macs** (Asahi Linux,
aarch64) — or any aarch64 Omarchy install — by pairing
[ncspot](https://github.com/hrkfdn/ncspot) with Omarchy's built-in `omarchy.media`
MPRIS bar widget.

## Why this exists

Spotify's official Linux client [has no aarch64 build](https://github.com/omacom/omarchy/issues/3208),
and the web player doesn't work either without a Widevine CDM. Meanwhile the
`extra/ncspot` package on Arch Linux ARM is stuck at `0.12.0`, built before
Spotify required OAuth login — so out of the box it fails with a generic
"connection error" no matter how correct your credentials are
([librespot#1330](https://github.com/librespot-org/librespot/issues/1330)).

This repo:
1. Documents/scripts building a current, OAuth-capable `ncspot` (via the AUR
   `ncspot-ncurses` package, built from source since no aarch64 binary exists
   upstream).
2. Ships a tiny Omarchy **service plugin** that keeps `ncspot` alive in a
   detached `tmux` session, so it survives across terminal windows and you
   don't have to babysit it.
3. Reuses Omarchy's existing first-party `omarchy.media` bar widget for the
   UI (now-playing, play/pause/skip, volume) — no custom widget needed, since
   it's already a generic MPRIS aggregator.
4. Patches a real upstream `ncspot` bug that leaves those bar-widget controls
   permanently disabled (see [Known ncspot issues](#known-ncspot-issues)
   below).
5. Adds one small bar-widget of its own — a music-note icon next to the media
   widget — since `omarchy.media` is a generic MPRIS control surface with no
   way to know ncspot's "window" is a detached `tmux` session. Click it to
   open the TUI back up.
6. Ships an optional [Y2K Windows Media Player theme](#themes) for the TUI
   itself — colors and format strings are all ncspot already supports, no
   patch needed.

## Requirements

- Omarchy 4.x (Quattro) on aarch64
- Spotify **Premium** (required for librespot-based playback)
- `tmux`

## Install

```sh
./install.sh
```

This builds `ncspot-ncurses` from the AUR, enables `omarchy.media`, and
registers this plugin with Omarchy. Or do it by hand:

```sh
git clone https://aur.archlinux.org/ncspot-ncurses.git
cd ncspot-ncurses
makepkg -si --ignorearch   # ignorearch: PKGBUILD says x86_64, but it's pure Rust and builds fine on aarch64

omarchy plugin enable omarchy.media
omarchy plugin add https://github.com/idrewlong/omarchy-ncspot-arm --enable
```

Then log in once. `omarchy-ncspot-login` attaches the keepalive session and
opens the OAuth URL in your browser for you (no copy-pasting a URL that
wraps across several terminal lines):

```sh
./omarchy-ncspot-login
```

Approve the login in your browser, then detach with `Ctrl+b` then `d`. From
then on the keepalive plugin restarts the session if it ever dies, and the
bar widget reflects whatever's playing.

(Equivalent by hand: `tmux new -s ncspot ncspot`, then read the OAuth URL
out of the pane yourself.)

## Browsing / queueing music

`ncspot` is a full TUI — reattach any time to search/browse/queue, either by
clicking the music-note bar-widget icon, or by hand:

```sh
tmux attach -d -t ncspot
```

Use `-d` (detach any other client first): tmux clamps a session shared by
multiple attached clients to the *smallest* one's size, which will silently
clip the bottom of ncspot's UI — that's exactly where the statusbar's
title/artist line lives, so a stray second attachment makes it look like
ncspot forgot how to show what's playing.

## Themes

[`themes/y2k-media-player.toml`](themes/y2k-media-player.toml) is a
config.toml drop-in for an early-2000s Windows Media Player look: black
background, a Luna-blue selection highlight, green LCD-style track text,
and `use_nerdfont = true` so ncspot's already-live shuffle/repeat/volume
status (bound to `Z`/`R`, on the right of the statusbar) draws as real icon
glyphs instead of bracket text — genuine current-state indicators, not
decoration, they just don't show anything until you've used shuffle or
repeat once.

It deliberately opens on the library (`initial_screen = "library"`) rather
than `cover`: this repo's build does support rendering real album art in
the terminal, but that view shows the *least* text — no title/artist
visible at all outside the statusbar — which is exactly the wrong tradeoff
when title/artist visibility is the actual goal. Press `F8` any time to
peek at cover art on purpose.

```sh
cp themes/y2k-media-player.toml ~/.config/ncspot/config.toml
```

Colors and format strings are config-only (see ncspot's own
[theming docs](https://github.com/hrkfdn/ncspot/blob/main/doc/users.md#theming));
tweak freely. Restart the session (`:quit` inside ncspot, or
`tmux kill-session -t ncspot` — the keepalive plugin respawns it) to pick up
theme and `initial_screen` changes; `:reload` only covers keybindings and
format strings.

## Known ncspot issues

**The bar widget's play/pause/next/prev buttons never enable themselves.**
ncspot's MPRIS server only emits `PropertiesChanged` for `PlaybackStatus`,
`Metadata`, `Volume`, and seek position — never for `CanGoNext`,
`CanGoPrevious`, `CanPlay`, `CanPause`, `CanSeek`, or `CanControl`. Those
start out `false` (nothing queued yet) and MPRIS clients that cache
capabilities instead of polling — including Quickshell's `Mpris` service,
which backs `omarchy.media` — never learn they became `true` once a track
loads. Confirmed against upstream `src/mpris.rs` (`ncspot` v1.4.0): the
`can_go_next`/`can_pause`/etc. getters are correct live, ncspot just never
tells anyone they changed.

`install.sh` patches this (see [`patches/`](patches)) by re-emitting all six
capability signals whenever playback status or the current track changes.
Verified end to end: without the patch, `omarchy-shell media playPause`
reports `unhandled` even while a track is actively playing; with it, a
`dbus-monitor` capture shows each `Can*` property firing its own
`PropertiesChanged` signal the moment the queue changes.

**ncspot's default keybindings don't match the usual media-player
convention.** `Space` queues the selected track/playlist, not
play/pause — that's `Shift+P`. [`themes/y2k-media-player.toml`](themes/y2k-media-player.toml)
remaps the familiar scheme (`Space`/`n`/`p`); `:reload` inside `ncspot`
picks up a keybinding-only change without a restart.

## License

MIT
