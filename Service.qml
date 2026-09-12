import QtQuick
import Quickshell.Io

Item {
  id: root

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  readonly property string sessionName: "ncspot"
  readonly property int checkIntervalMs: 15000

  function ensureRunning() {
    if (!ensureProcess.running) ensureProcess.running = true
  }

  Process {
    id: ensureProcess
    command: ["bash", "-lc",
      "tmux has-session -t " + root.sessionName + " 2>/dev/null || " +
      "tmux new-session -d -s " + root.sessionName + " ncspot"]
  }

  Timer {
    interval: root.checkIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.ensureRunning()
  }
}
