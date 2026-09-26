import QtQuick
import Quickshell.Io

// Keeps the background Spotify player (`spotify_player -d`) running, so the
// bar's mini player and Omarchy's media keys always have something to talk to.
// All the logic lives in bin/spotify-tui; see `ensure` there.
Item {
  id: root

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  readonly property string spotifyTui: String(Qt.resolvedUrl("bin/spotify-tui")).replace(/^file:\/\//, "")

  Process {
    id: ensureProcess
    command: [root.spotifyTui, "ensure"]
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!ensureProcess.running) ensureProcess.running = true
  }
}
