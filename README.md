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
   open the TUI back up. What each of the two widgets responds to is written
   down in [The bar widgets](#the-bar-widgets); `omarchy.media`'s next/prev
   are gestures with nothing on screen to hint at them.
6. Ships an optional [Y2K Windows Media Player theme](#themes) for the TUI
   itself — colors and format strings are all ncspot already supports, no
   patch needed.
7. Offers [spotify-player as an alternative backend](#choosing-a-player) for
   the same slot, with its own Y2K theme — no compile, no patch, real Sixel
   album art and a working visualizer.

## Choosing a player

Two TUIs can fill this repo's slot. Both are librespot-based, both handle
Spotify's OAuth requirement, both publish MPRIS so `omarchy.media` works.

```sh
./install.sh                          # ncspot (default)
./install.sh --player spotify-player  # spotify-player
```

The choice is recorded in `~/.config/omarchy-ncspot-arm/player`, which the
keepalive service and the bar-widget button both read on every use. It's
kept outside the plugin checkout so `omarchy plugin update` can't clobber
it, and it defaults to `ncspot` when absent — so an install that predates
this option keeps behaving exactly as it did.

Re-running `install.sh` with the other `--player` also stops the previous
player's `tmux` session. Nothing else ever would: the keepalive service only
looks at the session belonging to the *current* choice, so before this the
documented way to switch left the old backend running forever — two
librespot devices on one account, which is the state the next paragraph
warns about, reached by following the instructions.

|                          | ncspot                                | spotify-player                        |
| ------------------------ | ------------------------------------- | ------------------------------------- |
| aarch64 install          | AUR build from source (~10 min)       | `pacman -S spotify-player`, prebuilt  |
| MPRIS bar-widget controls| needs [our patch](patches)            | correct as shipped                    |
| Album art in the TUI     | `F8`, a full-screen page              | always visible, beside the track text |
| Visualizer               | none — no such feature exists         | 64-band frequency bars                |
| Lyrics                   | none                                  | dedicated page                        |
| Theme surface            | 19 fixed colors, xterm-256 quantized  | 18-color palette + 20 component styles, true 24-bit |

**Why ncspot is still the default.** It's what this repo has been shipping,
it works, and switching backends silently would be a worse answer than
offering the choice. Its one genuine edge is that it doesn't probe the
terminal for a graphics protocol, so it behaves identically whether the tmux
session was created attached or detached — see the
[headless caveat](#the-headless-caveat) below, which is the one rough edge
on the spotify-player path.

**Why spotify-player is worth switching to.** On aarch64 it costs one
`pacman -S` instead of a from-source Rust build, and it needs no patch at
all: `busctl` shows every MPRIS capability already `true` at startup.

```
$ busctl --user get-property org.mpris.MediaPlayer2.spotify_player \
    /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player CanPause
b true
$ omarchy-shell media playPause
ok
```

That `ok` is the whole reason [`patches/`](patches) exists for ncspot — an
unpatched ncspot answers `unhandled` there even mid-track.

**Don't run both at once.** They're two Spotify Connect devices on one
account and two MPRIS players competing for the bar widget, and the doubled
Web API traffic is enough on its own to earn a `429 Too Many Requests` from
Spotify (observed here: `retry_after_secs=15`, which stalls play/pause for
both). The session names differ (`ncspot` / `spotify-player`) so nothing
collides at the tmux level — that's a convenience for switching, not an
invitation to run a pair.

**What about spotify-tui / spotatui?** `spotify-tui` is
[archived by its author](https://github.com/Rigellute/spotify-tui/issues/1156)
and doesn't work with current Spotify auth. Its maintained successor
[`spotatui`](https://github.com/LargeModGames/spotatui) is a real project
with MPRIS and an FFT visualizer, but it's AUR-only — a from-source Rust
build, i.e. exactly the cost this repo exists to avoid — and its docs claim
no terminal graphics protocol at all, so no album art. spotify-player wins
both axes, so spotatui isn't packaged here.

## Requirements

- Omarchy 4.x (Quattro) on aarch64
- Spotify **Premium** (required for librespot-based playback)
- `tmux`, `jq`, and the `omarchy` CLI

`install.sh` checks for those three before it does anything. A missing `tmux`
in particular used to be invisible: the build succeeds, the plugin
registers, and then the keepalive service and the bar-widget button both
silently do nothing, because everything they do is a `tmux` invocation whose
failure they swallow.

## Install

```sh
./install.sh
```

This builds `ncspot-ncurses` from the AUR, drops the
[Y2K theme](#themes) into `~/.config/ncspot/config.toml`, enables
`omarchy.media`, and registers this plugin with Omarchy. Both `--player` paths
install their theme the same way now, and both keep whatever config was
already there as a `.bak` first — and if a `.bak` already exists they say so
and leave it alone rather than overwriting the backup of the backup.

It registers the plugin **from this checkout**, not from `origin`.
`omarchy plugin add` runs `git clone -- <source> <stage>`, and git clones a
local path as readily as a URL, so what omarchy-shell loads is the code
sitting here rather than whatever is currently on GitHub. It also used to
break outright on an SSH remote: `git remote get-url origin` hands back
`git@github.com:...`, and `omarchy-plugin-add` clones with
`GIT_TERMINAL_PROMPT=0` and `ssh -oBatchMode=yes`, so a passphrase-protected
key fails with nothing to answer the prompt on. git only clones committed
refs, so `install.sh` says so when the working tree has changes that won't
make the trip.

Or do it by hand:

```sh
git clone https://aur.archlinux.org/ncspot-ncurses.git
cd ncspot-ncurses
makepkg -si --ignorearch --nocheck   # ignorearch: PKGBUILD says x86_64, but it's pure Rust and builds fine on aarch64
                                      # nocheck: skip check(), a second cargo build with its own feature
                                      # set whose failure would otherwise kill an install this repo doesn't need

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

### Installing the spotify-player path instead

```sh
./install.sh --player spotify-player
./omarchy-spotify-player-login
```

No AUR, no patch, no compile — Arch Linux ARM ships a real aarch64 binary in
`[extra]`, built with the features that matter here. Check them yourself:

```
$ spotify_player features
  ✓ streaming   ✓ media-control   ✓ image   ✓ sixel   ✓ notify   ✓ daemon
```

Expect **two** browser approvals, not one. With streaming on, spotify-player
runs two independent OAuth flows under two different client IDs — the Web
API token (ncspot's client ID, cached as `<client_id>_token.json`) and the
librespot session (Spotify's own client ID, cached as `credentials.json`).
Spotify demands a separate approval for each, and the second URL only
appears after the first finishes, so a person watching the terminal will
often approve one, see it sit there, and assume it hung.
`omarchy-spotify-player-login` loops until the process exits and opens each
URL as it appears. Confirm both landed:

```
$ ls ~/.cache/spotify-player/
credentials.json  d420a117a32841c2b3474932e49fb54b_token.json  audio  image
```

Two things that script has to do that aren't obvious. It stops the keepalive
session first, because a second `spotify_player` would fight the running one
for the OAuth callback port (8989) and register a duplicate Connect device —
and then it has to *park a do-nothing session under the same name* for the
duration, because [`Service.qml`](Service.qml) re-checks every 15 seconds and
only asks whether a session of that name exists. Killing the session alone
would just have the keepalive respawn the player into the middle of the
login. And when it restarts the real session at the end it tags it
`@headless`, exactly as the keepalive service does, or the first thing you'd
see after a successful login is permanently blocky album art — see
[the headless caveat](#the-headless-caveat).

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

On the spotify-player path the session is named after the binary
(`tmux attach -d -t spotify-player`), and prefer the bar-widget icon to a
hand-rolled `attach`: the button also handles the
[headless caveat](#the-headless-caveat), which a bare `attach` does not.

Everything in this repo that names a session now writes it as `=ncspot`
rather than `ncspot`. A bare tmux target matches exactly, then as a *prefix*,
then as an fnmatch — so an unrelated session of your own called
`ncspot-scratch` satisfies `has-session -t ncspot`, and the `=` is what stops
a `kill-session` from finding it:

```
$ tmux new-session -d -s ncspot-scratch 'sleep 60'
$ tmux has-session -t ncspot-scratch && echo matched    # the real target
matched
$ tmux has-session -t ncspot-scratc && echo matched     # a prefix also matches
matched
$ tmux has-session -t "=ncspot-scratc" || echo rejected
can't find session: ncspot-scratc
rejected
```

Quote it if you type it yourself. Omarchy's default shell is `zsh`, where a
bare leading `=` is an equals-expansion — `=ncspot-scratc` becomes "the full
path of the command `ncspot-scratc`", and you get `ncspot-scratc not found`
from the shell before tmux ever sees the argument. The scripts here always
write `"=$s"`.

The prefix also only works on the session-target commands, which is not
obvious, and is why the `set-option` calls sitting right next to it stay bare:
`has-session`, `kill-session` and `attach-session` take `=`, while
`set-option`, `show-option` and `capture-pane` answer
`no such session: =ncspot` (checked against tmux 3.7).

### The window says "Media Player", the session is still called "ncspot"

`tmux`'s `status-left` defaults to echoing the session name, so the TUI
window's top-left used to read `ncspot` or `spotify-player` — i.e. it
announced which backend you happened to install, which is the one detail
everything else here works to make invisible. Every session this plugin
creates now gets a cosmetic relabel instead, black on the same `#c0c0c0`
silver both Y2K themes use for their transport bars:

```sh
tmux set-option -t "$s" status-left-length 20
tmux set-option -t "$s" status-left "#[fg=#000000,bg=#c0c0c0,bold] Media Player #[default] "
```

`status-left-length` has to go with it: tmux's default is 10, which clips the
label to `Media Pla`.

The session *name* is deliberately untouched. `install.sh`,
[`Service.qml`](Service.qml), [`OpenPlayerWidget.qml`](OpenPlayerWidget.qml)
and both login scripts all address the session by name, and the `@headless`
flag behind the [headless caveat](#the-headless-caveat) is a session option
keyed to it — so `tmux attach -d -t ncspot` still works exactly as documented
above, and a rename would have quietly broken five lookups to fix one label.

This is tmux's chrome, which is a different thing from ncspot's own in-app
statusbar (`statusbar_format` in
[`themes/y2k-media-player.toml`](themes/y2k-media-player.toml), the silver bar
across the bottom of the pane). The two are independent.

It's applied once, at session creation, in each of the four places that create
one — the keepalive service, the bar-widget button's create-if-missing
fallback, and both login scripts — so if you set your own `status-left` on the
session afterwards it stays yours (and a session you rolled by hand with
`tmux new -s ncspot ncspot` never gets it). The flip side is that a session
predating this keeps the old label until it's recreated:

```sh
tmux kill-session -t ncspot   # the keepalive plugin respawns it within 15s
```

## The bar widgets

Two widgets sit in the bar and they are not the same thing. Which one does
what is worth reading once, because between them they own every control this
setup has and only one of them looks like a button.

**`omarchy.media`** is Omarchy's own, and generic: it aggregates every MPRIS
player on the system. It is what shows now-playing and what drives transport.
Inline in the bar it draws exactly two things — a play/pause *state* glyph
and the scrolling title — and every control is a gesture on that glyph, with
nothing on screen to advertise any of them. From
`/usr/share/omarchy/shell/plugins/services/media/BarWidget.qml`:

| gesture      | action                        |
| ------------ | ----------------------------- |
| left click   | play/pause                    |
| middle click | next track                    |
| right click  | open the popup card           |
| scroll up    | previous track                |
| scroll down  | next track                    |

The right-click popup is the only place visible buttons exist: prev /
play-pause / next, the album art, title / artist / album, and — when more
than one MPRIS player is running — a list to pick which one the widget
follows.

One more thing in that file worth knowing before you conclude the install
failed: `visible: hasMedia`, where `hasMedia` needs a track title or artist.
Until something has been loaded the widget is not dimmed, it is **absent**.
A fresh login with nothing queued shows no media widget at all. Queue a
track and it appears.

**The music-note icon** (`󰝚`) is this repo's own widget,
[`OpenPlayerWidget.qml`](OpenPlayerWidget.qml), and it has exactly one job:
open the TUI. **Left click**, and only left click — middle and right are
deliberately inert, because right-click means "context menu" everywhere else
on the bar, `omarchy.media` right next door included, and opening a terminal
is a surprising answer to it. So there is one gesture here, not five.

It is always visible, including when `omarchy.media` isn't — which makes it
the thing to click when nothing is playing yet and the bar looks empty. If
opening fails (no `tmux`, a player binary that won't start), the terminal now
stays open with the reason in it; it used to flash and vanish, which looks
exactly like a bar icon that does nothing.

### The gap between the two icons

There is a few pixels of daylight between the play/pause glyph and the
music note, and it can't be closed from inside this repo. It isn't
inter-widget spacing — the bar's module list is `spacing: 0`
(`plugins/bar/Bar.qml`, the `horizontalModuleList` component), and a hidden
module contributes `implicitWidth: 0`. The whitespace is padding each widget
reserves inside its own slot:

- `omarchy.media` declares
  `implicitWidth: hasMedia ? row.implicitWidth + Style.space(14) : 0`, and the
  row inside it is centered — so half of that 14px (at the default spacing
  scale) sits to the right of the glyph.
- this repo's icon uses `BarIconButton`, whose slot is `Style.bar.iconSlot`
  (27px) around a `Style.bar.iconCanvas` (16px) glyph, i.e. ~5px each side.
  That is the same slot every other Omarchy bar icon uses, and shrinking it
  here would put this one icon out of rhythm with the rest of the bar.

The larger share is `omarchy.media`'s, in a system-owned file that an Omarchy
update overwrites, and `omarchy plugin validate`'s manifest schema has no key
for widget spacing, grouping or ordering hints — there is no plugin API to
influence another widget's layout. Editing that file in place is also not the
pattern here: [`patches/`](patches) patches ncspot's *source* through a real
patch file applied at build time, which survives updates; a live edit to
`/usr/share/omarchy/...` survives nothing. If you want it tighter today,
`omarchy plugin clone omarchy.media` makes a user-owned copy you can edit,
at the cost of freezing it at today's version.

## Themes

Two Y2K Windows Media Player themes ship here, one per player. They share a
palette on purpose — the same Luna blue, the same LCD lime, the same silver
— so the two backends look like the same product.

- [`themes/y2k-media-player.toml`](themes/y2k-media-player.toml) — ncspot
- [`themes/spotify-player/`](themes/spotify-player) — spotify-player
  (`theme.toml` + `app.toml`)

`install.sh` copies whichever backend's theme file(s) apply into place
automatically, and keeps any existing file it would overwrite as `.bak`
(only on the first run that actually differs — re-running `install.sh`
doesn't clobber that backup with the theme's own file).

### ncspot

[`themes/y2k-media-player.toml`](themes/y2k-media-player.toml) is a
config.toml drop-in for an early-2000s Windows Media Player look.
`install.sh` installs it automatically; to apply it by hand (or reapply it
after editing `config.toml` yourself):

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

### spotify-player

[`themes/spotify-player/`](themes/spotify-player) is the same look with more
to put it on. `theme.toml` carries the colors, `app.toml` the layout and
format strings; both go in `~/.config/spotify-player/`.

**What it gets you that the ncspot theme can't.** A persistent Now Playing
panel across the top of *every* page — cover art, track text and seek bar
all still visible while you browse a playlist — a real
green→amber→red VU-meter visualizer under it, and a lyrics page. WMP's
column headers come back as black-on-silver `table_header`, which is one
line of config and the single most Win32-looking thing in the UI.

**The colors are exact here.** spotify-player is ratatui/crossterm, so it
emits real 24-bit SGR rather than snapping to the xterm-256 cube the way the
ncurses ncspot build has to. You can read the theme straight off the wire:

```
$ tmux capture-pane -t spotify-player -p -e | grep -o '38;2;[0-9;]*' | sort -u
38;2;0;224;0      # #00e000 LCD lime  -> the playing track
38;2;107;173;247  # #6badf7 Luna blue -> block titles, album
38;2;212;212;212  # #d4d4d4 silver    -> list text
38;2;63;143;239   # #3f8fef           -> seek bar fill, on a #6e6e6e groove
```

**The visualizer is real, and it's really your colors.** It draws 64
log-scale frequency bands, colored by amplitude between the theme's
`low`/`mid`/`high`. Captured mid-track, the bar cells come back as
`38;2;195;209;0`, `38;2;255;179;10`, `38;2;255;136;24` — interpolations
along this theme's `#00c000 → #ffd700 → #ff3b30` ramp, not upstream's
blue→green→red default. It renders only while audio is streaming through
spotify-player's own librespot device; the render is gated on
`is_local_streaming_active()`, so handing playback to another Spotify
Connect device makes the whole area vanish. That's upstream behavior.

**Same TOML gotcha, worse blast radius.** Every bare top-level key has to
sit *above* the first `[table]` header, exactly as with the ncspot theme —
and spotify-player's config struct ignores misplaced keys without even a log
warning. An earlier draft of `app.toml` put `cover_img_width`,
`playback_format` and `enable_audio_visualization` after `[layout.library]`
and spent a while looking like the visualizer was broken. Don't trust the
file; read back what the app actually loaded:

```sh
grep -o 'enable_audio_visualization: [a-z]*' ~/.cache/spotify-player/*.log
```

### The headless caveat

This is the one place the spotify-player path is genuinely rougher than
ncspot, and it comes from how it renders album art.

Album art works — verifiably. Captured off the raw terminal stream in
`foot`, both bare and through `tmux`, spotify-player emits a real Sixel
image: DCS header `ESC P 9;1;0 q "1;1;180;182`, a 180×182px raster with its
own color registers, ~127 KB of payload. `tmux` 3.7 is built with Sixel
support and passes `foot`'s capability through — `tmux display -p
'#{client_termfeatures}'` lists `sixel`, and DA1 inside tmux answers
`ESC[?1;2;4c`, where the `4` is Sixel.

The catch: `ratatui-image` picks a protocol **exactly once, at startup**, by
querying the terminal over stdio (`Picker::from_query_stdio` in
`src/ui/mod.rs`). There is no config option and no env var to force it
afterwards. A tmux session created *detached* — which is exactly what a
keepalive service does — has no attached client to answer that query, so the
probe fails and the process is stuck on half-block art for its whole life:

```
$ tmux new-session -d -s spotify-player spotify_player
$ grep -o 'Image protocol: [A-Za-z]*' ~/.cache/spotify-player/*.log
Image protocol: Halfblocks
```

So [`Service.qml`](Service.qml) tags any session it had to create blind with
`@headless`, and [`OpenPlayerWidget.qml`](OpenPlayerWidget.qml) recreates
that session with a client attached when you open the TUI, which makes the
probe succeed:

```
$ tmux show-option -qv -t spotify-player @headless
1
# ... click the bar widget ...
$ grep -o 'Image protocol: [A-Za-z]*' ~/.cache/spotify-player/*.log
Image protocol: Sixel
```

Recreating restarts the process, so it's skipped whenever something is
actually playing — clicking "open" must never cut off music. The cost of
that rule is that if you start music before ever opening the TUI, you keep
blocky art until the next restart. ncspot has no equivalent problem: it
blits Sixel from its own code and never probes.

### Album art in the bar widget

Worth knowing before anyone writes QML for it: Omarchy's `omarchy.media`
widget **already** shows cover art. Its popup card binds `trackArtUrl`
straight into an `Image` (see
`/usr/share/omarchy/shell/plugins/services/media/BarWidget.qml`, the
`Image { source: root.activePlayer.trackArtUrl }` block), with a music-note
glyph as the fallback when it's empty.

Both players feed it. spotify-player publishes a real CDN URL:

```
$ busctl --user --json=short get-property org.mpris.MediaPlayer2.spotify_player \
    /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Metadata
mpris:artUrl = 'https://i.scdn.co/image/ab67616d0000b273ffe7f1d3a6c317cf21cbbc83'
```

and ncspot fills the same key from `cover_url()` (`src/mpris.rs:166`) once a
track is loaded — it reads empty only when nothing is queued. So there's
nothing to build here: no custom cover-art panel, no IPC bridge to ncspot's
socket. The bar widget already does it.

## Things that look broken and aren't

Everything here is explained in full somewhere above. This is the index,
because each one is a case where the correct behavior and a failed install
look identical from the bar.

| What you see | What it is |
| ------------ | ---------- |
| No media widget in the bar at all | `omarchy.media` sets `visible: hasMedia` and hides itself until a track has a title or artist. Queue something. [details](#the-bar-widgets) |
| A play/pause glyph and nothing else — no next/prev | They exist, as gestures: middle-click for next, scroll for prev/next, right-click for the popup with real buttons. [details](#the-bar-widgets) |
| The popup's play/pause/skip buttons are greyed out (ncspot) | Unpatched ncspot never signals its MPRIS capabilities. This is what [`patches/`](patches) fixes; `install.sh` applies it. [details](#known-ncspot-issues) |
| ncspot opens on a track list, no album art anywhere | Deliberate: `initial_screen = "library"`, because the cover page hides title and artist. Press `F8` for cover art. [details](#ncspot) |
| ncspot's shuffle/repeat glyphs are missing from the transport bar | They're live state, and ncspot draws an empty string when both are off. Lowercase `z` and `r` — uppercase isn't bound. [details](#ncspot) |
| ncspot's bottom title/artist line disappeared | A second `tmux` client is attached and tmux clamped the session to the smaller one. Attach with `-d`. [details](#browsing--queueing-music) |
| spotify-player's login hangs after you approve it | There are **two** approvals, and the second URL only appears after the first finishes. [details](#installing-the-spotify-player-path-instead) |
| spotify-player's album art is blocky | Its graphics-protocol probe needs an attached terminal at startup. Click the music-note icon while nothing is playing. [details](#the-headless-caveat) |
| The `tmux` window is labeled "Media Player", not the player's name | Cosmetic `status-left` override; the session is still named `ncspot` / `spotify-player`. [details](#the-window-says-media-player-the-session-is-still-called-ncspot) |
| A gap between the play/pause glyph and the music-note icon | Padding inside `omarchy.media`'s own slot, in a system-owned file with no plugin API to reach it. [details](#the-gap-between-the-two-icons) |

One case that really is a failure, and now says so: `omarchy-ncspot-login` and
`omarchy-spotify-player-login` both refuse to run if their binary isn't
installed. They used to start a `tmux` session around a command that exited
immediately, find no login prompt, report "probably already logged in", and
then fail to attach to a session that no longer existed — three misleading
messages for one missing package.

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
