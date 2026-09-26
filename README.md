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
- **`spotify-tui`** on your `PATH`: `open`, `login`, `logout`, `client-id`,
  `restart`, `status`.
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

## Use your own Spotify app (recommended)

Out of the box, spotify-player makes its Web API calls (and it makes them
even for play/pause and skips) under ncspot's client ID, which every ncspot
and spotify-player install in the world shares. When that shared quota runs
out, Spotify answers `429 Too Many Requests` and the controls stop working
until it recovers. Your own app gets its own quota:

1. In the [Spotify developer dashboard](https://developer.spotify.com/dashboard),
   **Create app**. Name and description can be anything.
2. **Redirect URI:** exactly `http://127.0.0.1:8989/login` (`127.0.0.1`,
   not `localhost`; `http`, no trailing slash). Click **Add**.
3. Tick **Web API**, accept the terms, **Save**.
4. Copy the **Client ID** from the app's settings (not the secret), then:

   ```sh
   spotify-tui client-id <your-client-id>
   ```

That's one browser approval, for your app. The ncspot token and librespot
login are already cached and are reused. spotify-player still keeps the
shared ID as a fallback for a few playlist endpoints Spotify restricts for new
apps, and to retry any request your app gets refused, so there's no option to
drop it entirely. Apps start in development mode, which only admits
allowlisted users; if sign-in says your account isn't registered, add it
under **Settings → User Management**. `spotify-tui client-id --reset` goes
back to the shared ID.

The ID lives in `~/.config/spotify-player/client_id`, read by `app.toml`'s
`client_id_command`, so the shipped config works with or without it.

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

- **Rate limits on the shared client ID.** Until you
  [use your own app](#use-your-own-spotify-app-recommended), play/pause,
  skips, shuffle and repeat fail whenever the shared quota is exhausted.
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
