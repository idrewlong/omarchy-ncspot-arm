import QtQuick
import Quickshell.Io

Item {
  id: root

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  readonly property int checkIntervalMs: 15000

  function ensureRunning() {
    if (!ensureProcess.running) ensureProcess.running = true
  }

  // Which player to keep alive is a user choice recorded by install.sh in
  // ~/.config/omarchy-ncspot-arm/player ("ncspot" or "spotify-player"), and
  // it's resolved in the shell rather than in QML on purpose: the file lives
  // outside the plugin checkout so `omarchy plugin update` can't clobber it,
  // and reading it fresh on every tick means switching players takes effect
  // without restarting omarchy-shell. Missing file => ncspot, which is what
  // every install before this option existed was running.
  //
  // The tmux session is named after the player, so the two can't collide if
  // someone has both installed -- though running both at once is a bad idea
  // (two Spotify Connect devices on one account, two MPRIS players competing
  // for the bar widget, and double the Web API traffic, which is enough to
  // earn a 429 from Spotify).
  Process {
    id: ensureProcess
    command: ["bash", "-lc",
      "p=$(cat \"${XDG_CONFIG_HOME:-$HOME/.config}\"/omarchy-ncspot-arm/player 2>/dev/null || echo ncspot); " +
      "case \"$p\" in spotify-player) s=spotify-player; c=spotify_player;; *) s=ncspot; c=ncspot;; esac; " +
      // "=" is tmux's exact-match target prefix. Without it a target also
      // matches as a prefix and then as an fnmatch, so an unrelated session
      // named e.g. "ncspot-scratch" would satisfy this check and the player
      // would never be started. Note it works on the session-target commands
      // only -- has-session, kill-session and attach-session accept it;
      // set-option, show-option and capture-pane answer "no such session: =x"
      // (checked against tmux 3.7), which is why those stay bare below.
      "tmux has-session -t \"=$s\" 2>/dev/null && exit 0; " +
      "tmux new-session -d -s \"$s\" \"$c\" || exit 0; " +
      // Tag the session as created blind. spotify-player probes the terminal
      // for a graphics protocol exactly once at startup, over stdio; a
      // session with no attached client has nobody to answer, so it falls
      // back to half-block album art permanently. The bar-widget button
      // reads this flag and recreates the session with a client attached
      // (when nothing is playing) so the probe can succeed. Harmless for
      // ncspot, which renders cover art from its own Sixel blitter and
      // doesn't probe.
      "tmux set-option -t \"$s\" @headless 1 2>/dev/null || true; " +
      // Cosmetic relabel of tmux's own status-left, which defaults to echoing
      // the session name -- so the TUI window's top-left read "ncspot" or
      // "spotify-player", i.e. exactly the backend detail the rest of this
      // repo works to make invisible. Black on the same #c0c0c0 silver both
      // Y2K themes use for their transport bar.
      //
      // The session *name* is deliberately untouched: install.sh, this
      // service, OpenPlayerWidget.qml and both login scripts all address the
      // session by name, and @headless above is a session option keyed to it.
      // This is tmux chrome only, and it is a different thing from ncspot's
      // in-app statusbar (themes/y2k-media-player.toml's statusbar_format).
      //
      // status-left-length has to go with it: tmux's default is 10, which
      // would clip the label to "Media Pla".
      //
      // Applied once, at creation, rather than on every tick -- a user who
      // then sets their own status-left on this session keeps it. Sessions
      // created elsewhere get the same two lines at their own creation site.
      "tmux set-option -t \"$s\" status-left-length 20 2>/dev/null || true; " +
      "tmux set-option -t \"$s\" status-left " +
      "\"#[fg=#000000,bg=#c0c0c0,bold] Media Player #[default] \" 2>/dev/null || true"]
  }

  Timer {
    interval: root.checkIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.ensureRunning()
  }
}
