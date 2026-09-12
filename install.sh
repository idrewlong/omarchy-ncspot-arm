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
tmp="$(mktemp -d)"
git clone https://aur.archlinux.org/ncspot-ncurses.git "$tmp/ncspot-ncurses"
(cd "$tmp/ncspot-ncurses" && makepkg -si --ignorearch)
rm -rf "$tmp"

echo "==> Enabling Omarchy's built-in Media (MPRIS) bar widget"
omarchy plugin enable omarchy.media

echo "==> Installing this keepalive plugin"
omarchy plugin add "$(git -C "$(dirname "${BASH_SOURCE[0]}")" remote get-url origin 2>/dev/null || echo "https://github.com/idrewlong/omarchy-ncspot-arm")" --enable

cat <<'EOF'

==> Done. One manual step remains: log in to Spotify once.

    tmux new -s ncspot ncspot

Follow the OAuth prompt (opens your browser). Once logged in and playing,
detach with Ctrl+b then d -- the keepalive service will keep the session
alive from here on, and the Media bar widget will show now-playing/controls.
EOF
