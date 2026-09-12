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
config.toml drop-in for an early-2000s Windows Media Player look:

```sh
cp themes/y2k-media-player.toml ~/.config/ncspot/config.toml
```

**What it gets you.** A black "Now Playing" field, LCD-lime text on the
currently-playing track, white-on-Luna-blue selection (with Windows' flat
grey selection for panes that don't have focus), a blue seek bar in a
recessed grey groove, and a silver transport bar across the bottom with
black text. The playlist columns are remapped to WMP's Now Playing order —
Title / Artist / Length — and `use_nerdfont = true` turns ncspot's bracket
text (`[R]`/`[Z]`/`[U]`) into real icon glyphs and gives saved tracks a
heart. `library_tabs` drops the two least WMP-era tabs (Podcasts, Browse)
down to four, and `hide_display_names = true` strips the "whose library did
this come from" username ncspot otherwise prints next to shared tracks.

`notify = true` is also set — without it, the `[notification_format]` table
below is dead config, since ncspot defaults notifications off and never
reads `title`/`body` unless this is on.

**What it can't get you.** ncspot is an ncurses TUI: there is no skin
chrome, no window bezel, and **no visualizer** — ncspot has no
audio-reactive rendering of any kind (there's no such feature in the v1.4.0
source). There's no "now playing" arrow in the playlist gutter either,
because no format-string placeholder exposes which row is playing; that row
is marked by color alone. And the album column doesn't exist — ncspot gives
exactly three slots and Title/Artist/Length fill them.

**The transport bar is real, though.** It's not drawn-on decoration:
left-click toggles play/pause, left-click on the seek bar jumps to that
position, and the scroll wheel over the `[nn%]` readout changes volume. The
play/pause glyph at the far left is a live state indicator.

The shuffle and repeat glyphs on the right are live state too — which is
why there's nothing there at first. ncspot draws an empty string when
shuffle and repeat are off, so they only appear once you turn them on. The
keys are lowercase **`z`** (shuffle) and **`r`** (repeat, cycling off →
repeat-playlist → repeat-track); uppercase `Z`/`R` aren't bound to
anything, so pressing those makes it look broken.

It deliberately opens on the library (`initial_screen = "library"`) rather
than `cover`: this repo's build does support rendering real album art in
the terminal, but that view shows the *least* text — no title/artist
visible at all outside the statusbar — which is exactly the wrong tradeoff
when title/artist visibility is the actual goal. Press `F8` any time to
peek at cover art on purpose (`cover_max_scale = 2` keeps it from filling
the pane with a soft blur).

**Colors.** ncspot passes these to cursive's parser, which takes
`black`/`red`/`green`/`yellow`/`blue`/`magenta`/`cyan`/`white`, each
optionally prefixed `light ` or `dark `, plus `default`, plus hex
(`#rrggbb`). **`gray` is not in that list** — `gray` and `light gray` fail
to parse and silently fall back to a default with only a log warning
(`ncspot -d <logfile>` to see it), which is how an earlier version of this
theme ended up with a statusbar that was never actually silver. This theme
uses hex throughout to avoid that. Note that this package builds ncspot
against the ncurses backend, which quantizes hex to the xterm-256 palette
rather than emitting truecolor — greys land on the fine 24-step ramp, other
colors snap to the 6×6×6 cube.

See ncspot's own
[user docs](https://github.com/hrkfdn/ncspot/blob/main/doc/users.md) and
tweak freely. Restart the session (`:quit` inside ncspot, or
`tmux kill-session -t ncspot` — the keepalive plugin respawns it) to pick up
theme and `initial_screen` changes; `:reload` only covers keybindings and
format strings.

One gotcha if you edit the file: `statusbar_format` is a top-level key, so
it has to stay *above* the `[track_format]` table. TOML assigns any bare key
written after a table header to that table, and ncspot then silently never
sees it.

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
