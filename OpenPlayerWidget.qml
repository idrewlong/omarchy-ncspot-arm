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
      // Left button only. WidgetButton forwards middle and right clicks here
      // too, and opening a terminal on a right-click is the wrong answer to a
      // gesture that means "context menu" everywhere else on the bar --
      // including on the omarchy.media widget sitting next to this one, where
      // right-click opens its popup.
      if (b !== Qt.LeftButton) return

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
        // "=" forces an exact session-name match; without it tmux also matches
        // a target as a prefix, and this one is a kill. It goes on
        // kill-session and attach-session but not on show-option above, which
        // rejects it outright ("no such session: =x" on tmux 3.7).
        "tmux kill-session -t \"=$s\" 2>/dev/null; fi; " +
        // The `tmux new` fallback is the path that has to create the session
        // *attached* (that is the whole point of the @headless dance above),
        // so the cosmetic status-left relabel rides along as a tmux command
        // sequence rather than a follow-up command -- `tmux new` without -d
        // blocks until the client detaches, so anything written after it
        // would only run once the window was already closed. Same two options
        // Service.qml sets at its own creation site; see the comment there
        // for why the session name itself stays as-is.
        //
        // And a trailing failure branch, because this runs in a terminal that
        // Omarchy closes the instant the command returns: without it, a broken
        // tmux or a missing player binary makes the window flash open and
        // vanish, which is indistinguishable from the bar icon doing nothing
        // at all. Hold the window open long enough to read why.
        "tmux attach -d -t \"=$s\" || tmux new -s \"$s\" \"$c\" " +
        "\\; set-option -t \"$s\" status-left-length 20 " +
        "\\; set-option -t \"$s\" status-left \"#[fg=#000000,bg=#c0c0c0,bold] Media Player #[default] \" " +
        "|| { echo; echo Could not open the Spotify TUI: neither attaching nor starting " +
        "tmux session $s running $c worked.; echo Press Enter to close.; read -r _; }'")
    }
  }
}
