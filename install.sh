#!/usr/bin/env bash
# Sets up ncspot (OAuth-capable build) + this keepalive plugin on Omarchy/aarch64.
set -euo pipefail

if [[ "$(uname -m)" != "aarch64" ]]; then
  echo "This is only needed on aarch64 (e.g. Omarchy on Apple Silicon via Asahi)." >&2
  echo "On x86_64, 'pacman -S ncspot' already ships an OAuth-capable build." >&2
  exit 1
fi

echo "==> Building ncspot-ncurses (OAuth-capable, v1.4.0+) from AUR"
echo "    (the aarch64 'extra/ncspot' package predates Spotify's OAuth requirement)"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

echo "==> Enabling Omarchy's built-in Media (MPRIS) bar widget"
omarchy plugin enable omarchy.media

plugin_id="$(jq -r '.id' "$repo_dir/manifest.json")"
if omarchy plugin list --json | jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' >/dev/null; then
  echo "==> Keepalive plugin already installed, skipping"
else
  echo "==> Installing this keepalive plugin"
  omarchy plugin add "$(git -C "$repo_dir" remote get-url origin 2>/dev/null || echo "https://github.com/idrewlong/omarchy-ncspot-arm")" --enable
fi

cat <<EOF

==> Done. One manual step remains: log in to Spotify once.

    $repo_dir/omarchy-ncspot-login

Approve the login in your browser, then detach with Ctrl+b then d -- the
keepalive service will keep the session alive from here on, and the Media
bar widget will show now-playing/controls.
EOF
