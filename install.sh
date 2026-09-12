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
  patch_file="$repo_dir/patches/mpris-emit-capabilities-changed.patch"
  if [[ -f "$patch_file" ]]; then
    echo "==> Patching ncspot's MPRIS server so the media bar widget's controls work"
    echo "    (upstream never signals CanPlay/CanPause/CanGoNext/CanGoPrevious"
    echo "     changes, so MPRIS clients that cache them -- like Quickshell's"
    echo "     Mpris service -- see play/pause/skip permanently disabled)"
    sed -i '/^prepare() {/,/^}/{
      /^}/i\  patch -Np1 -i "'"$patch_file"'"
    }' "$tmp/ncspot-ncurses/PKGBUILD"
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
  (cd "$tmp/ncspot-ncurses" && makepkg -si --ignorearch --noconfirm)
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
  mkdir -p "$cfg"
  for f in app.toml theme.toml; do
    if [[ -e "$cfg/$f" ]] && ! cmp -s "$repo_dir/themes/spotify-player/$f" "$cfg/$f"; then
      cp -n "$cfg/$f" "$cfg/$f.bak" && echo "    kept your existing $f as $f.bak"
    fi
    cp "$repo_dir/themes/spotify-player/$f" "$cfg/$f"
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
printf '%s\n' "$player" > "$state_dir/player"
echo "==> Recorded player choice in $state_dir/player"

echo "==> Enabling Omarchy's built-in Media (MPRIS) bar widget"
omarchy plugin enable omarchy.media

plugin_id="$(jq -r '.id' "$repo_dir/manifest.json")"
if omarchy plugin list --json | jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' >/dev/null; then
  echo "==> Keepalive plugin already installed, skipping"
else
  echo "==> Installing this keepalive plugin"
  omarchy plugin add "$(git -C "$repo_dir" remote get-url origin 2>/dev/null || echo "https://github.com/idrewlong/omarchy-ncspot-arm")" --enable
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
