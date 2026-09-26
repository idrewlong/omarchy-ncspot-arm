#!/usr/bin/env bash
# Sets up Spotify on aarch64 Omarchy: spotify-player as a background player,
# a music icon in the bar with a hover mini player, and SUPER+SHIFT+M opening
# the full TUI. Safe to re-run; it updates an existing install.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
plugin_id="$(jq -r '.id' "$repo_dir/manifest.json")"
plugin_dir="$config/omarchy/plugins/$plugin_id"

missing=()
for cmd in jq curl omarchy; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "missing required commands: ${missing[*]}" >&2
  exit 1
fi

# Put one of this repo's config files in place, keeping whatever was there as
# a .bak first (once -- an existing .bak is never overwritten).
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

# Arch Linux ARM ships a prebuilt aarch64 spotify-player with streaming, MPRIS,
# Sixel album art and daemon mode (check with `spotify_player features`).
echo "==> Installing spotify-player"
sudo pacman -S --needed --noconfirm spotify-player

echo "==> Installing the spotify-player config + Y2K theme"
for f in app.toml theme.toml; do
  install_config_file "$repo_dir/themes/spotify-player/$f" "$config/spotify-player/$f"
done

# Earlier versions of this repo ran ncspot (or spotify-player) in a detached
# tmux session. Stop those so they don't show up as a second Spotify device.
# ncspot itself is left installed.
for s in ncspot spotify-player; do
  if tmux has-session -t "=$s" 2>/dev/null; then
    echo "==> Stopping the old '$s' tmux session"
    tmux kill-session -t "=$s"
  fi
done
rm -f "$config/omarchy-ncspot-arm/player"
rmdir "$config/omarchy-ncspot-arm" 2>/dev/null || true

if omarchy plugin list --json | jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' >/dev/null; then
  echo "==> Updating the plugin"
  omarchy plugin update "$plugin_id" --yes
else
  echo "==> Installing the plugin"
  # Install from this checkout rather than GitHub, so what omarchy-shell loads
  # is the code sitting here. git clones committed refs only.
  if git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
    plugin_source="$repo_dir"
    [[ -z "$(git -C "$repo_dir" status --porcelain)" ]] ||
      echo "    note: uncommitted changes in $repo_dir are not installed"
  else
    plugin_source="https://github.com/idrewlong/omarchy-ncspot-arm"
  fi
  omarchy plugin add "$plugin_source" --enable --yes
fi

# The music icon replaces Omarchy's media widget in the bar: it shows the same
# controls on hover, plus shuffle/repeat and a way back to the full player.
shell_json="$config/omarchy/shell.json"
if [[ -f "$shell_json" ]] && jq -e '.bar.layout' "$shell_json" >/dev/null; then
  updated="$(jq --arg id "$plugin_id" '
    def has_ours: [.bar.layout[][]? | select(.id == $id)] | length > 0;
    if has_ours then
      .bar.layout |= map_values(map(select(.id != "omarchy.media")))
    else
      .bar.layout |= map_values(map(if .id == "omarchy.media" then {id: $id} else . end))
    end' "$shell_json")"
  if [[ "$updated" != "$(cat "$shell_json")" ]]; then
    echo "==> Replacing the Media widget in the bar with the music icon"
    cp "$shell_json" "$shell_json.bak"
    printf '%s\n' "$updated" > "$shell_json"
  fi
fi

echo "==> Linking spotify-tui into ~/.local/bin"
mkdir -p "$HOME/.local/bin"
ln -sfn "$plugin_dir/bin/spotify-tui" "$HOME/.local/bin/spotify-tui"

# Omarchy's own SUPER+SHIFT+M runs omarchy-launch-spotify, which falls through
# to an installer that can't work on aarch64. Point it at this player instead,
# in a marked block so re-running replaces rather than duplicates it.
bindings="$config/hypr/bindings.lua"
if [[ -f "$bindings" ]]; then
  echo "==> Binding SUPER+SHIFT+M to the Spotify TUI"
  sed -i '/^-- omarchy-ncspot-arm: begin/,/^-- omarchy-ncspot-arm: end/d' "$bindings"
  cat >> "$bindings" <<EOF
-- omarchy-ncspot-arm: begin
hl.unbind("SUPER + SHIFT + M")
o.bind("SUPER + SHIFT + M", "Music", "$HOME/.local/bin/spotify-tui open")
o.window("org.omarchy.spotify-tui", { tag = "+floating-window" })
-- omarchy-ncspot-arm: end
EOF
fi

cache="${XDG_CACHE_HOME:-$HOME/.cache}/spotify-player"
if [[ -s "$cache/credentials.json" ]]; then
  chmod 700 "$cache"
  chmod 600 "$cache"/*.json 2>/dev/null || true
  "$plugin_dir/bin/spotify-tui" restart
  echo
  echo "==> Done. Hover the music icon in the bar, or press SUPER+SHIFT+M."
else
  echo
  echo "==> Done. One step left -- sign in to Spotify:"
  echo
  echo "    spotify-tui login"
fi
