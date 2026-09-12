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
      // --app-id=TUI.float gets Omarchy's default floating+centered+875x600
      // treatment (see default/hypr/apps/system.lua) instead of whatever
      // sliver a tiling layout has free -- ncspot needs real rows to fit its
      // tab bar, list, and two-line statusbar without clipping the bottom
      // line (where the title/artist live). `attach -d` detaches any other
      // client on the session first: tmux clamps a shared session to the
      // *smallest* attached client's size, so a second, smaller terminal
      // left open elsewhere would silently shrink this one back down.
      root.bar.run("omarchy-launch-terminal --app-id=TUI.float bash -c 'tmux attach -d -t ncspot || tmux new -s ncspot ncspot'")
    }
  }
}
