import QtQuick
import qs.Ui

// A small bar icon, separate from Omarchy's own omarchy.media widget, whose
// only job is to open the Spotify TUI. omarchy.media is a generic MPRIS
// aggregator with no idea the player's "window" is a detached tmux session,
// so there's no way to get from "now playing" back to the actual player
// without this: its own click handlers are already play/pause (left), next
// (middle), and a controls popup (right).
BarWidget {
  id: root
  moduleName: "io.github.idrewlong.ncspot-keepalive"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰝚"
    tooltipText: "Open Spotify TUI"
    onPressed: function(b) {
      // --app-id=TUI.float gets Omarchy's default floating+centered+875x600
      // treatment (see default/hypr/apps/system.lua) instead of whatever
      // sliver a tiling layout has free -- both players need real rows to
      // fit their panes without clipping the bottom line, and for
      // spotify-player those rows are also what the cover art is drawn into.
      //
      // `attach -d` detaches any other client on the session first: tmux
      // clamps a shared session to the *smallest* attached client's size, so
      // a second, smaller terminal left open elsewhere would silently shrink
      // this one back down.
      //
      // The @headless dance only applies to spotify-player, and it exists
      // because of a hard constraint in how it renders album art:
      // ratatui-image picks a graphics protocol exactly once, at startup,
      // by querying the terminal over stdio (Picker::from_query_stdio in
      // src/ui/mod.rs). A tmux session created detached -- which is what the
      // keepalive service does -- has no attached client to answer that
      // query, so the probe fails and the process is stuck on half-block art
      // for its whole lifetime. There is no config option or env var to
      // force the protocol after the fact.
      //
      // So the keepalive tags any session it creates blind with @headless,
      // and opening the TUI recreates that session with a client attached,
      // which makes the probe succeed (verified: the log line goes from
      // "Image protocol: Halfblocks" to "Image protocol: Sixel").
      // Recreating restarts the process, so it is skipped whenever something
      // is actually playing -- clicking "open" must never cut off music.
      // Worst case there you keep blocky art until the next restart.
      root.bar.run("omarchy-launch-terminal --app-id=TUI.float bash -c '" +
        "p=$(cat \"${XDG_CONFIG_HOME:-$HOME/.config}\"/omarchy-ncspot-arm/player 2>/dev/null || echo ncspot); " +
        "case \"$p\" in spotify-player) s=spotify-player; c=spotify_player;; *) s=ncspot; c=ncspot;; esac; " +
        "if [ \"$s\" = spotify-player ] && [ \"$(tmux show-option -qv -t \"$s\" @headless 2>/dev/null)\" = 1 ] && " +
        "! busctl --user get-property org.mpris.MediaPlayer2.spotify_player /org/mpris/MediaPlayer2 " +
        "org.mpris.MediaPlayer2.Player PlaybackStatus 2>/dev/null | grep -q Playing; then " +
        "tmux kill-session -t \"$s\" 2>/dev/null; fi; " +
        "tmux attach -d -t \"$s\" || tmux new -s \"$s\" \"$c\"'")
    }
  }
}
