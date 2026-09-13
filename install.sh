#!/usr/bin/env bash
# Sets up a Spotify TUI + this keepalive plugin on Omarchy/aarch64.
#
#   ./install.sh                          # ncspot (default)
#   ./install.sh --player spotify-player  # spotify-player
#
# Both back the same thing: a detached tmux session running a librespot-based
# TUI client, whose MPRIS server drives Omarchy's omarchy.media bar widget.
# They differ in what they cost to install and what the TUI can draw --
# see the README's "Choosing a player" section.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
player="ncspot"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --player) player="${2:?--player needs a value}"; shift 2 ;;
    --player=*) player="${1#--player=}"; shift ;;
    -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$player" in
  ncspot|spotify-player) ;;
  *) echo "--player must be 'ncspot' or 'spotify-player' (got: $player)" >&2; exit 2 ;;
esac

# Fail here rather than several minutes into a Rust build, or -- worse -- after
# a successful install, where a missing tmux makes the keepalive service and
# the bar-widget button silently do nothing at all.
missing=()
for cmd in tmux jq omarchy; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "missing required commands: ${missing[*]}" >&2
  exit 1
fi

# Put one of this repo's config/theme files in place, keeping whatever was
# already there as a .bak first. `cp -n "$dst" "$dst.bak"` is not enough on its
# own: when the .bak already exists, -n makes cp do nothing *and still exit 0*,
# so an unconditional message after it announces a backup that never happened.
install_config_file() {
  local src="$1" dst="$2" name
  name="$(basename "$dst")"
  mkdir -p "$(dirname "$dst")"
  if [[ -e "$dst" ]] && ! cmp -s "$src" "$dst"; then
    if [[ -e "$dst.bak" ]]; then
      echo "    replacing $name; $name.bak already exists and is left untouched"
    else
      cp "$dst" "$dst.bak"
      echo "    kept your existing $name as $name.bak"
    fi
  fi
  cp "$src" "$dst"
}

install_ncspot() {
  # Only the ncspot path is aarch64-specific: it exists purely to work around
  # extra/ncspot on Arch Linux ARM predating Spotify's OAuth requirement.
  if [[ "$(uname -m)" != "aarch64" ]]; then
    echo "The ncspot path is only needed on aarch64 (e.g. Omarchy on Apple Silicon via Asahi)." >&2
    echo "On x86_64, 'pacman -S ncspot' already ships an OAuth-capable build." >&2
    exit 1
  fi

  echo "==> Building ncspot-ncurses (OAuth-capable, v1.4.0+) from AUR"
  echo "    (the aarch64 'extra/ncspot' package predates Spotify's OAuth requirement)"
  # Build on real disk, not /tmp: a Rust release build's target/ dir runs to
  # multiple GB, and /tmp is commonly a small RAM-backed tmpfs that a build
  # this size can fill outright (seen in the wild: linker SIGBUS from a full
  # tmpfs, indistinguishable at a glance from a real compiler bug).
  tmp="$(mktemp -d -p /var/tmp)"
  trap 'rm -rf "$tmp"' EXIT
  git clone https://aur.archlinux.org/ncspot-ncurses.git "$tmp/ncspot-ncurses"

  # The patch is not optional: an unpatched build installs cleanly and leaves
  # the bar widget's controls permanently disabled, which is the single bug
  # this whole repo exists to fix. So check that it is here, that the PKGBUILD
  # still has the prepare() hook the injection targets, and that the injection
  # actually landed -- a silent sed no-op here would ship a broken install and
  # look like a success.
  patch_file="$repo_dir/patches/mpris-emit-capabilities-changed.patch"
  if [[ ! -f "$patch_file" ]]; then
    echo "missing $patch_file -- an unpatched ncspot leaves the bar widget's controls disabled" >&2
    exit 1
  fi
  echo "==> Patching ncspot's MPRIS server so the media bar widget's controls work"
  echo "    (upstream never signals CanPlay/CanPause/CanGoNext/CanGoPrevious"
  echo "     changes, so MPRIS clients that cache them -- like Quickshell's"
  echo "     Mpris service -- see play/pause/skip permanently disabled)"
  if ! grep -q '^prepare() {' "$tmp/ncspot-ncurses/PKGBUILD"; then
    echo "the AUR PKGBUILD no longer has a prepare() function to hook the patch into." >&2
    echo "Apply patches/mpris-emit-capabilities-changed.patch by hand before building." >&2
    exit 1
  fi
  sed -i '/^prepare() {/,/^}/{
    /^}/i\  patch -Np1 -i "'"$patch_file"'"
  }' "$tmp/ncspot-ncurses/PKGBUILD"
  if ! grep -qF "patch -Np1 -i \"$patch_file\"" "$tmp/ncspot-ncurses/PKGBUILD"; then
    echo "failed to inject the patch step into the PKGBUILD." >&2
    exit 1
  fi

  # pandoc-cli (only used to generate the man page) isn't built for aarch64 on
  # Arch Linux ARM -- not in the official repos, not in the AUR -- so drop it
  # rather than fail the whole build over a man page.
  echo "==> Skipping man page generation (pandoc-cli has no aarch64 build)"
  sed -i \
    -e "s/'pandoc-cli'//" \
    -e '/^\s*pandoc README\.md/d' \
    -e '/ncspot\.1/d' \
    "$tmp/ncspot-ncurses/PKGBUILD"
  # --nocheck: check() runs `cargo test` with its own feature set, a second
  # compile distinct from the actual build() -- a test failure there kills an
  # otherwise-good install over code this repo never exercises.
  (cd "$tmp/ncspot-ncurses" && makepkg -si --ignorearch --noconfirm --nocheck)

  echo "==> Installing the Y2K Windows Media Player theme"
  install_config_file "$repo_dir/themes/y2k-media-player.toml" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/ncspot/config.toml"
}

install_spotify_player() {
  # No AUR, no patch, no compile: Arch Linux ARM ships a real aarch64 binary
  # of spotify-player in [extra], built with the features that matter here --
  # streaming, media-control (MPRIS), image + sixel (album art), notify,
  # daemon. Check them yourself with `spotify_player features`.
  #
  # And no MPRIS patch: unlike ncspot, spotify-player reports its Can*
  # capabilities as true from startup, so omarchy.media's play/pause/skip
  # buttons are live without any source change.
  echo "==> Installing spotify-player from [extra] (prebuilt aarch64, no compile)"
  sudo pacman -S --needed --noconfirm spotify-player

  echo "==> Installing the Y2K Windows Media Player config + theme"
  cfg="${XDG_CONFIG_HOME:-$HOME/.config}/spotify-player"
  for f in app.toml theme.toml; do
    install_config_file "$repo_dir/themes/spotify-player/$f" "$cfg/$f"
  done
}

echo "==> Selected player: $player"
case "$player" in
  ncspot) install_ncspot ;;
  spotify-player) install_spotify_player ;;
esac

# Both the keepalive service and the bar-widget button read this to decide
# which binary/tmux session they manage. Kept outside the plugin checkout so
# `omarchy plugin update` can't clobber the choice.
state_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-ncspot-arm"
mkdir -p "$state_dir"
previous="$(cat "$state_dir/player" 2>/dev/null || true)"
printf '%s\n' "$player" > "$state_dir/player"
echo "==> Recorded player choice in $state_dir/player"

# Switching backends used to leave the old one's tmux session running forever:
# nothing ever kills it, and the keepalive service only looks at the session
# belonging to the *current* choice. That leaves two librespot devices on one
# account and two MPRIS players competing for the bar widget -- the exact state
# the README's "Don't run both at once" warns about, arrived at by following
# the documented way to switch. So stop the one being switched away from.
#
# "=" is tmux's exact-match prefix. Without it a target is also matched as a
# prefix, so a session named e.g. "ncspot-scratch" could be the thing that gets
# killed. Worth the two characters anywhere a kill is involved.
if [[ -n "$previous" && "$previous" != "$player" ]]; then
  case "$previous" in
    ncspot|spotify-player)
      if tmux has-session -t "=$previous" 2>/dev/null; then
        echo "==> Stopping the previous player's session ($previous)"
        tmux kill-session -t "=$previous"
      fi
      ;;
  esac
fi

echo "==> Enabling Omarchy's built-in Media (MPRIS) bar widget"
omarchy plugin enable omarchy.media

plugin_id="$(jq -r '.id' "$repo_dir/manifest.json")"
if omarchy plugin list --json | jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' >/dev/null; then
  echo "==> Keepalive plugin already installed, skipping"
else
  echo "==> Installing this keepalive plugin"
  # Install from this checkout, not from `origin`. `omarchy plugin add` runs
  # `git clone -- <source> <stage>`, and git clones a local path as readily as a
  # URL, so the plugin omarchy-shell ends up loading is the code sitting here --
  # the code you just read -- rather than whatever is currently on GitHub.
  #
  # Going through origin also broke outright for an SSH remote: `git remote
  # get-url origin` hands back git@github.com:... and omarchy-plugin-add clones
  # with GIT_TERMINAL_PROMPT=0 and `ssh -oBatchMode=yes`, so a key with a
  # passphrase fails with no way to answer the prompt.
  #
  # git clones committed refs only, so say so if the working tree has anything
  # that won't make the trip.
  if git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
    plugin_source="$repo_dir"
    if [[ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]]; then
      echo "    note: uncommitted/untracked changes in $repo_dir are not cloned"
    fi
  else
    plugin_source="https://github.com/idrewlong/omarchy-ncspot-arm"
  fi
  omarchy plugin add "$plugin_source" --enable
fi

if [[ "$player" == "ncspot" ]]; then
  login_cmd="$repo_dir/omarchy-ncspot-login"
else
  login_cmd="$repo_dir/omarchy-spotify-player-login"
fi

cat <<EOF

==> Done. One manual step remains: log in to Spotify once.

    $login_cmd

Approve the login in your browser -- the keepalive service will keep the
session alive from here on, and the Media bar widget will show
now-playing/controls.
EOF
