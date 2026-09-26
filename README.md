# omarchy-ncspot-arm

Spotify for **Omarchy on Apple Silicon Macs** (Asahi Linux, aarch64), or any
aarch64 Omarchy install: [spotify-player](https://github.com/aome510/spotify-player)
running in the background, a music icon in the bar with a hover mini player,
and `SUPER+SHIFT+M` for the full TUI.

## Why this exists

Spotify's official Linux client [has no aarch64 build](https://github.com/omacom/omarchy/issues/3208),
the web player needs a Widevine CDM that doesn't exist there either, and
Omarchy's own Music key falls through to an installer that can't work on ARM.
Arch Linux ARM does ship a prebuilt spotify-player, a librespot-based client,
which is everything this repo builds on.

(The name is historical: this started as an ncspot setup. ncspot needed a
from-source build and an MPRIS patch on aarch64; spotify-player needs
neither, and can run as a daemon, so it replaced it in 2.0.)

## What you get

- **A background player.** `spotify_player -d` streams the audio and appears
  as one Spotify Connect device, so you can also drive it from your phone.
  The plugin's service keeps it running.
- **A music icon in the bar.** Hover it for a mini player: cover, track,
  progress, and shuffle / previous / play-pause / next / repeat. Click it for
  the full TUI. Middle-click toggles playback; scroll skips. It replaces
  Omarchy's Media widget in the bar.
- **The full TUI on `SUPER+SHIFT+M`**, floating, focused if it's already
  open. It's a remote for the background player, not a second player.
- **Instant track notifications** with cover art, updating in place as you
  skip.
- **`spotify-tui`** on your `PATH`: `open`, `login`, `logout`, `restart`,
  `status`.
- **A Y2K Windows Media Player theme** for the TUI.

## Requirements

- Omarchy 4.x on aarch64
- Spotify **Premium** (librespot playback requires it)
- `jq`, `curl`, and the `omarchy` CLI

## Install

```sh
./install.sh
spotify-tui login
```

`install.sh` installs spotify-player from `[extra]`, puts its config and theme
in `~/.config/spotify-player/` (keeping yours as `.bak`), installs this
plugin, swaps the bar's Media widget for the music icon, links `spotify-tui`
into `~/.local/bin`, and rebinds `SUPER+SHIFT+M` in a marked block at the end
of `~/.config/hypr/bindings.lua`. Re-running it updates everything in place.

**Signing in takes two browser approvals.** spotify-player signs in twice
under two client IDs: once for the Web API (library, search), once for
librespot (playback). The second URL only appears after the first is
approved, which looks like a hang if you don't expect it. `spotify-tui login`
opens each one as it shows up. If you're not signed in, the plugin sends a
notification you can click to start it.

Credentials are cached in `~/.cache/spotify-player/`; the login locks them to
mode 600, since spotify-player writes them world-readable.

## How it works

```
spotify_player -d  ── audio (librespot), MPRIS, Spotify Connect device
   │  player_event_hook_command
   └─ bin/spotify-player-event ── notification + now.json ──> bar mini player
bin/spotify-tui open ── spotify_player (TUI, remote only)
Service.qml ── `spotify-tui ensure` every 15s
```

- **Why a daemon.** The TUI can't run detached: it reads the terminal's
  cursor position at startup and exits when nothing answers. The daemon has
  no terminal at all.
- **Why the TUI is only a remote.** `enable_streaming = "DaemonOnly"` in
  `app.toml`. If the TUI streamed too, you'd have two Spotify devices, two
  MPRIS players, and every notification twice. It's opened with its own MPRIS
  server and notifications switched off for the same reason.
- **Why a hook instead of MPRIS for track changes.** spotify-player only
  refreshes its playback state 1s after librespot reports a change (and again
  2s later), so its MPRIS data and built-in notifications arrive 1–3s after
  the music changes. `bin/spotify-player-event` runs on librespot's `Playing`
  event and has the track on screen in well under a second. It gets title,
  artist and cover from Spotify's public embed page rather than the Web API
  (see below), falling back to the API if that page ever changes shape.
- **Shuffle and repeat** go through `spotify_player playback shuffle|repeat`,
  since spotify-player's MPRIS server doesn't implement them. Their state is
  read with `spotify_player get key playback`, which the daemon answers from
  memory.

## Known limitations

- **Rate limits.** spotify-player uses a Web API client ID shared with every
  other spotify-player and ncspot install, so Spotify's `429 Too Many
  Requests` comes easily, and it stalls play/pause while it lasts. This repo
  keeps its own API calls to a minimum for that reason.
- **No visualizer in the TUI.** The theme turns it on, but it only draws in
  the instance that's streaming, and that's the daemon.
- **Omarchy's media OSD and `omarchy-shell media` commands** still see the
  player through MPRIS, so they inherit its 1–3s lag.

## Theme

[`themes/spotify-player/`](themes/spotify-player) is a Y2K Windows Media
Player look: `theme.toml` has the colors, `app.toml` the layout, format
strings and behavior. A persistent Now Playing panel sits across the top of
every page (cover art, track, seek bar), WMP-style black-on-silver column
headers, and exact 24-bit color.

**TOML gotcha.** Every bare top-level key in `app.toml` has to sit *above*
the first `[table]` header. spotify-player silently ignores misplaced keys,
without even a log warning. Check what it actually loaded:

```sh
grep -o 'enable_streaming: [A-Za-z]*' ~/.cache/spotify-player/*.log | tail -1
```

## Upgrading from the ncspot version

`install.sh` stops the old `ncspot` / `spotify-player` tmux sessions and
removes `~/.config/omarchy-ncspot-arm/`. It leaves ncspot itself installed;
remove it with `sudo pacman -R ncspot-ncurses` if you don't want it.

## License

MIT
