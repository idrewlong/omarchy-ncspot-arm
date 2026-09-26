import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

// A music icon for the bar. Hovering it shows a mini player (cover, track,
// progress, shuffle / previous / play-pause / next / repeat); clicking it
// opens the full TUI. Middle-click toggles playback, the wheel skips.
BarWidget {
  id: root
  moduleName: "io.github.idrewlong.ncspot-keepalive"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string spotifyTui: String(Qt.resolvedUrl("bin/spotify-tui")).replace(/^file:\/\//, "")

  // The background player's own MPRIS entry -- not omarchy.media's "active
  // player", which could be a browser tab.
  readonly property var player: {
    var list = Mpris.players ? Mpris.players.values : []
    for (var i = 0; i < list.length; i++)
      if (String(list[i].dbusName || "").indexOf("org.mpris.MediaPlayer2.spotify_player") === 0)
        return list[i]
    return null
  }

  // spotify-player-event writes the new track here the moment librespot
  // starts it. MPRIS gets the same data 1-3s later (spotify-player waits on a
  // delayed Web API refresh), so this wins whenever it's present.
  property var now: null
  FileView {
    id: nowFile
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-spotify/now.json"
    watchChanges: true
    printErrors: false
    // text() is stale inside the change signal; reload and parse in onLoaded.
    onFileChanged: reload()
    onLoaded: {
      try { root.now = JSON.parse(text()) } catch (e) { root.now = null }
    }
    onLoadFailed: root.now = null
  }
  readonly property bool useNow: player !== null && now !== null && now.title !== ""

  readonly property string title: useNow ? now.title : (player ? (player.trackTitle || "") : "")
  readonly property string artist: useNow ? now.artists : (player ? (player.trackArtist || "") : "")
  readonly property string artUrl: useNow && now.cover
    ? "file://" + now.cover
    : (player && player.trackArtUrl ? player.trackArtUrl : "")

  // Play/pause flips immediately on click; MPRIS confirms within ~1s.
  property var playingOverride: null
  readonly property bool isPlaying: playingOverride !== null ? playingOverride : (player ? player.isPlaying : false)
  Connections {
    target: root.player
    ignoreUnknownSignals: true
    function onIsPlayingChanged() { root.playingOverride = null }
  }
  Timer { id: overrideExpiry; interval: 2500; onTriggered: root.playingOverride = null }

  function togglePlaying() {
    if (!player) return
    playingOverride = !isPlaying
    overrideExpiry.restart()
    player.togglePlaying()
  }

  // Shuffle/repeat: spotify-player's MPRIS server has neither, so they go
  // through its CLI. State is read back with `get key playback`, which the
  // daemon answers from memory -- no Web API request, no rate-limit cost.
  property bool shuffle: false
  property string repeatState: "off"   // off | context | track

  Process {
    id: stateProcess
    command: ["spotify_player", "get", "key", "playback"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var p = JSON.parse(text)
          if (!p) return
          root.shuffle = !!p.shuffle_state
          root.repeatState = p.repeat_state || "off"
        } catch (e) {}
      }
    }
  }
  Process { id: controlProcess }

  function refreshState() {
    if (player && !stateProcess.running) stateProcess.running = true
  }

  function runControl(action) {
    controlProcess.command = ["spotify_player", "playback", action]
    controlProcess.running = true
    stateRefreshLater.restart()
  }

  function toggleShuffle() {
    shuffle = !shuffle
    runControl("shuffle")
  }

  function cycleRepeat() {
    repeatState = repeatState === "off" ? "context" : repeatState === "context" ? "track" : "off"
    runControl("repeat")
  }
  Timer { id: stateRefreshLater; interval: 1500; onTriggered: root.refreshState() }

  // --- hover-open popup -------------------------------------------------

  property bool popupOpen: false
  function close() { popupOpen = false }

  readonly property bool hovering: iconHover.hovered || popup.containsMouse
  onHoveringChanged: {
    if (hovering) {
      closeTimer.stop()
      if (!popupOpen) openTimer.restart()
    } else {
      openTimer.stop()
      closeTimer.restart()
    }
  }
  // A short open delay so sweeping the pointer across the bar doesn't flash
  // the card; a longer close delay to cross the gap between bar and card.
  Timer { id: openTimer; interval: 180; onTriggered: root.popupOpen = true }
  Timer { id: closeTimer; interval: 350; onTriggered: root.popupOpen = false }

  onPopupOpenChanged: if (popupOpen) refreshState()
  Timer {
    interval: 1000
    repeat: true
    running: root.popupOpen
    onTriggered: {
      // MprisPlayer.position only moves when asked to.
      if (root.player) root.player.positionChanged()
      if ((++tick % 3) === 0) root.refreshState()
    }
    property int tick: 0
  }

  HoverHandler { id: iconHover }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰝚"
    dimmed: !root.isPlaying
    onPressed: function(b) {
      if (b === Qt.MiddleButton) { root.togglePlaying(); return }
      if (b !== Qt.LeftButton) return
      root.popupOpen = false
      root.openFullPlayer()
    }
    onWheelMoved: function(delta) {
      if (!root.player) return
      if (delta > 0) root.player.previous()
      else root.player.next()
    }
  }

  // Opens the TUI, or focuses it if already open. See bin/spotify-tui.
  function openFullPlayer() {
    Quickshell.execDetached([root.spotifyTui, "open"])
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    triggerMode: "hover"
    contentWidth: popup.fittedContentWidth(Style.space(300))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        width: parent.width
        spacing: Style.space(10)

        BorderSurface {
          width: Style.space(64)
          height: Style.space(64)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

          Image {
            anchors.fill: parent
            anchors.margins: Style.space(2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.artUrl
            visible: source !== "" && status === Image.Ready
          }

          Text {
            anchors.centerIn: parent
            visible: root.artUrl === ""
            text: "󰝚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }

        Column {
          width: parent.width - Style.space(74)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.title || (root.player ? "Nothing playing" : "Player not running")
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            visible: text !== ""
            textFormat: Text.PlainText
            text: root.artist
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }
      }

      // Progress. Hidden while MPRIS still describes the previous track
      // (its length would be wrong for the one the hook just announced).
      Rectangle {
        readonly property bool valid: root.player !== null && root.player.length > 0
          && (!root.useNow || root.player.trackTitle === root.now.title)
        width: parent.width
        height: Style.space(3)
        radius: height / 2
        color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.18)
        opacity: valid ? 1 : 0

        Rectangle {
          height: parent.height
          radius: parent.radius
          color: Color.accent
          width: parent.valid ? parent.width * Math.min(1, root.player.position / root.player.length) : 0
          Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(4)

        Button {
          iconText: root.shuffle ? "󰒟" : "󰒞"
          selected: root.shuffle
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.player !== null
          opacity: enabled ? (root.shuffle ? 1.0 : 0.55) : 0.25
          onClicked: root.toggleShuffle()
        }

        Button {
          iconText: "󰒮"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.player !== null && root.player.canGoPrevious
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.player.previous()
        }

        Button {
          iconText: root.isPlaying ? "󰏤" : "󰐊"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.panelGap
          verticalPadding: Style.spacing.controlPaddingY
          iconSize: Style.font.iconLarge
          enabled: root.player !== null && (root.player.canTogglePlaying || root.player.canPlay || root.player.canPause)
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.togglePlaying()
        }

        Button {
          iconText: "󰒭"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.player !== null && root.player.canGoNext
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.player.next()
        }

        Button {
          iconText: root.repeatState === "track" ? "󰑘" : "󰑖"
          selected: root.repeatState !== "off"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.player !== null
          opacity: enabled ? (root.repeatState !== "off" ? 1.0 : 0.55) : 0.25
          onClicked: root.cycleRepeat()
        }
      }
    }
  }
}
