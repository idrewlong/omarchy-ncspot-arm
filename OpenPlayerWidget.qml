import QtQuick
import qs.Ui

// A small bar icon, separate from Omarchy's own omarchy.media widget, whose
// only job is to open the ncspot TUI. omarchy.media is a generic MPRIS
// aggregator with no idea ncspot's "window" is a detached tmux session, so
// there's no way to get from "now playing" back to the actual player without
// this: its own click handlers are already play/pause (left), next (middle),
// and a controls popup (right).
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
    tooltipText: "Open ncspot"
    onPressed: function(b) {
      root.bar.run("omarchy-launch-terminal bash -c 'tmux attach -t ncspot || tmux new -s ncspot ncspot'")
    }
  }
}
