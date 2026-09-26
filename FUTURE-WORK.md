# Future work

Ideas discussed and deliberately not acted on yet: parked here to pick up
later, not a commitment or a roadmap.

## Rebuild from the ground up in Rust

A purpose-built daemon on [librespot](https://github.com/librespot-org/librespot)
instead of spotify-player: stream audio, serve MPRIS, and push state to the
bar the instant librespot reports it, over its own IPC (a socket or a watched
state file), with no Web API polling and no hardcoded refresh delays. The
QML mini player and any richer custom UIs (library browser, search palette)
would talk to it directly. Main costs: a Rust build per release (so it needs
prebuilt aarch64 packages to stay a one-command install), and owning the
Spotify auth flow ourselves. Revisit once the current QML UI settles.

## Fix the MPRIS lag upstream

spotify-player only refreshes playback 1s after a librespot event
(`update_playback_non_blocking` in `client/mod.rs`), and its MPRIS loop polls
that state once a second (`media_control.rs`). This repo's hook works around
it for the notification and the bar icon, but Omarchy's media OSD and media
keys still see the lag. An upstream PR that updates the player state straight
from librespot's `TrackChanged`/`Playing` events would fix it for everyone.

## Use your own Spotify client ID

spotify-player's `client_id` setting (or `client_id_command`) lets each user
register their own Spotify app instead of sharing ncspot's ID, whose rate
limit every ncspot and spotify-player install draws from. That's the real fix
for the `429 Too Many Requests` stalls, at the cost of a setup step (creating
a Spotify developer app). Worth an optional `spotify-tui` subcommand that
walks through it.

## Follow the active Omarchy theme

The Y2K theme is fixed hex. Omarchy renders templates from
`~/.config/omarchy/themed/*.tpl` into the current theme directory on every
theme switch; a `spotify-player.toml.tpl` there, symlinked as
`~/.config/spotify-player/theme.toml`, would make the TUI follow the desktop
theme, with Y2K as an opt-in. The mini player already follows it.

## More mini-player features

- Seek by clicking the progress bar (MPRIS `SetPosition` works).
- Like/unlike the current track (`spotify_player like`).
- Switch the playing Spotify Connect device (`spotify_player connect`).
- Volume on scroll over the card.

## uninstall.sh

Remove the plugin, the `~/.local/bin/spotify-tui` link and the
`bindings.lua` block; put `omarchy.media` back in the bar; restore the
`.bak` configs; optionally remove spotify-player and the credential cache.
