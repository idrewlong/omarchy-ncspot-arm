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

Then log in once, interactively (OAuth, opens your browser — no password
typed anywhere):

```sh
tmux new -s ncspot ncspot
```

Detach with `Ctrl+b` then `d`. From then on the keepalive plugin restarts the
session if it ever dies, and the bar widget reflects whatever's playing.

## Browsing / queueing music

`ncspot` is a full TUI — reattach any time to search/browse/queue:

```sh
tmux attach -t ncspot
```

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
play/pause — that's `Shift+P`. If you want the familiar scheme, add to
`~/.config/ncspot/config.toml`:

```toml
[keybindings]
"Space" = "playpause"
"n" = "next"
"p" = "previous"
```

(Run `:reload` inside `ncspot`, or restart the session, to pick up config
changes.)

## License

MIT
