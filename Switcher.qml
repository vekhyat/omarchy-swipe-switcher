import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Windows-style window switcher for the current workspace, with live previews.
//
// Swipe: the touchpad reader below follows a 3-finger swipe as the fingers
// move (Hyprland's own gesture actions only fire once the fingers lift). The
// switcher opens once the swipe is clearly horizontal, the selection moves one
// window per stepDistance of travel, left to right as the windows sit on
// screen and stopping at the ends, and lifting the fingers picks.
//
// Alt+Tab: the global shortcuts below, bound in the user's Hyprland config
// (see README): most recent window first, wrapping, and releasing Alt picks.
//
// next/prev over IPC (no hold) pick once they stop for commitDelay ms.
// Clicking a preview or pressing Enter picks at once, Escape cancels.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property var windows: []
  property int selectedIndex: 0
  // Swipes that arrive while the window list is still loading.
  property int pendingSteps: 0
  // Fingers are on the touchpad: wait for release instead of the timer.
  property bool held: false
  // Fingers lifted before the window list finished loading.
  property bool pendingRelease: false
  // "swipe": left to right on screen, stopping at the ends. "keys" (Alt+Tab):
  // most recent first, wrapping around, as on Windows.
  property string mode: "swipe"
  // Last good preview per window address (grab results, kept alive so their
  // urls stay valid). Hyprland gives no frames for a window that is off
  // screen, such as one scrolled away on the scrolling layout, so those show
  // the frame from the last time it was on screen instead.
  property var snapshots: ({})

  readonly property int commitDelay: 650

  // Touchpad swipe tuning. Distances are libinput's unaccelerated units; a
  // full slide across a laptop touchpad is roughly 400.
  readonly property int swipeFingers: 3
  readonly property real stepDistance: 105
  // Travel before deciding whether the swipe is horizontal (ours) or vertical
  // (left to Hyprland).
  readonly property real lockDistance: 15
  property bool swipeActive: false
  property string swipeLock: ""
  property real swipeDx: 0
  property real swipeDy: 0

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color accent: Commons.Color.accent
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int gap: Style.space(12)
  property int previewHeight: Style.space(170)
  // Previews shrink so every window fits on screen.
  property int tileWidth: {
    var count = Math.max(1, root.windows.length)
    var available = panel.width - Style.gapsOut * 4 - root.gap * (count + 1)
    return Math.max(Style.space(110), Math.min(Style.space(280), Math.floor(available / count)))
  }

  function step(delta) {
    if (root.opened) {
      root.select(root.selectedIndex + delta)
      if (!root.held) commitTimer.restart()
      return
    }
    root.pendingSteps += delta
    if (!clientsProc.running) clientsProc.running = true
  }

  function hold(mode) {
    root.mode = mode
    root.held = true
    root.pendingRelease = false
    commitTimer.stop()
  }

  function release() {
    root.held = false
    if (clientsProc.running) root.pendingRelease = true
    else if (root.opened) root.commit()
  }

  function keyStep(delta) {
    if (!root.opened && !clientsProc.running) root.hold("keys")
    root.step(delta)
  }

  // A swipe stops at the ends instead of wrapping, so swiping right never
  // lands on a window to the left. Alt+Tab wraps.
  function select(index) {
    var n = root.windows.length
    if (n === 0) return
    if (root.mode === "keys") root.selectedIndex = ((index % n) + n) % n
    else root.selectedIndex = Math.max(0, Math.min(n - 1, index))
  }

  // Left to right as the windows sit on screen (top to bottom on ties), so
  // swiping right moves right and the tiles keep their places between
  // switches. Hyprland's own client list reorders whenever a window is raised.
  function orderWindows(clients) {
    return clients.slice().sort(function(a, b) {
      return (a.at[0] - b.at[0]) || (a.at[1] - b.at[1]) || (a.address < b.address ? -1 : 1)
    })
  }

  function toplevelFor(address) {
    var bare = String(address).replace(/^0x/, "")
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      if (toplevels[i].address === bare) return toplevels[i].wayland
    }
    return null
  }

  function iconFor(appId) {
    var entry = DesktopEntries.heuristicLookup(appId)
    return Quickshell.iconPath(entry && entry.icon ? entry.icon : appId, true)
  }

  function load(text) {
    var steps = root.pendingSteps
    var released = root.pendingRelease
    root.pendingSteps = 0
    root.pendingRelease = false
    var clients
    try {
      clients = JSON.parse(text)
    } catch (e) {
      return
    }
    var workspace = Hyprland.focusedWorkspace
    var workspaceId = workspace ? workspace.id : null
    var here = clients.filter(function(c) {
      return c.mapped && !c.hidden && c.workspace && c.workspace.id === workspaceId
    })
    if (here.length < 2 || steps === 0) return
    root.forgetClosed(clients)

    // Start from the focused window, whatever order the list is in.
    var ordered = root.mode === "keys"
      ? here.slice().sort(function(a, b) { return a.focusHistoryID - b.focusHistoryID })
      : root.orderWindows(here)
    var active = 0
    for (var i = 1; i < ordered.length; i++) {
      if (ordered[i].focusHistoryID < ordered[active].focusHistoryID) active = i
    }

    root.windows = ordered.map(function(c) {
      return {
        address: String(c.address),
        title: String(c.title || c.class || ""),
        appId: String(c.class || ""),
        toplevel: root.toplevelFor(c.address)
      }
    })
    root.select(active + steps)
    root.opened = true
    if (released) root.commit()
    else if (!root.held) commitTimer.restart()
  }

  function remember(address, view) {
    view.grabToImage(function(result) {
      var next = Object.assign({}, root.snapshots)
      next[address] = result
      root.snapshots = next
    })
  }

  function forgetClosed(clients) {
    var open = {}
    for (var i = 0; i < clients.length; i++) open[String(clients[i].address)] = true
    var next = {}
    for (var address in root.snapshots) {
      if (open[address]) next[address] = root.snapshots[address]
    }
    root.snapshots = next
  }

  // One `libinput debug-events` line, already filtered to swipe events.
  function readSwipe(line) {
    var m = /GESTURE_SWIPE_(BEGIN|UPDATE|END)\s+(?:\d+\s+)?\+[\d.]+s\s+(\d+)\s*(.*)/.exec(line)
    if (!m) return
    var kind = m[1]
    if (kind === "BEGIN") {
      root.swipeActive = parseInt(m[2]) === root.swipeFingers
      root.swipeLock = ""
      root.swipeDx = 0
      root.swipeDy = 0
      return
    }
    if (kind === "END") {
      if (root.swipeActive && root.swipeLock === "horizontal") root.release()
      root.swipeActive = false
      return
    }
    if (!root.swipeActive) return
    var d = /\(\s*(-?[\d.]+)\/\s*(-?[\d.]+) unaccelerated\)/.exec(m[3])
    if (!d) return
    root.swipeDx += parseFloat(d[1])
    root.swipeDy += parseFloat(d[2])

    if (root.swipeLock === "" && Math.abs(root.swipeDx) + Math.abs(root.swipeDy) >= root.lockDistance) {
      root.swipeLock = Math.abs(root.swipeDx) > Math.abs(root.swipeDy) ? "horizontal" : "vertical"
      if (root.swipeLock === "horizontal") {
        // Open on the neighbouring window right away, as Windows does.
        root.hold("swipe")
        root.step(root.swipeDx > 0 ? 1 : -1)
        root.swipeDx = 0
      }
    }
    if (root.swipeLock !== "horizontal") return

    // Fingers moving right (positive dx) select the window to the right.
    var steps = Math.trunc(root.swipeDx / root.stepDistance)
    if (steps !== 0) {
      root.swipeDx -= steps * root.stepDistance
      root.step(steps)
    }
  }

  function commit() {
    commitTimer.stop()
    var win = root.windows[root.selectedIndex]
    root.cancel()
    if (!win || !/^0x[0-9a-f]+$/i.test(win.address)) return
    var target = "window = \"address:" + win.address + "\""
    Hyprland.dispatch("hl.dsp.focus({ " + target + " })")
    Hyprland.dispatch("hl.dsp.window.alter_zorder({ mode = \"top\", " + target + " })")
  }

  function cancel() {
    commitTimer.stop()
    root.held = false
    root.opened = false
    root.windows = []
  }

  Timer {
    id: commitTimer
    interval: root.commitDelay
    onTriggered: root.commit()
  }

  Process {
    id: clientsProc
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.load(text)
    }
  }

  // The touchpad's swipe events, as the fingers move. Needs libinput-tools and
  // the user in the `input` group. Retried in case the touchpad comes back
  // after a resume; given up after maxQuickFailures runs that end within a
  // minute, such as without read access.
  readonly property int maxQuickFailures: 5
  property int quickFailures: 0
  property real touchpadStarted: 0

  Process {
    id: touchpadProc
    running: true
    onRunningChanged: if (running) root.touchpadStarted = Date.now()
    command: ["bash", "-c",
      "for f in /sys/class/input/event*/device/name; do " +
      "  if grep -qi touchpad \"$f\"; then " +
      "    d=${f#/sys/class/input/}; " +
      // grep is the process the shell owns. setpriv ends libinput as soon as
      // grep stops (shell restart, plugin reload), which a broken pipe alone
      // would only do at the touchpad's next event.
      "    exec grep --line-buffered GESTURE_SWIPE < <(setpriv --pdeathsig TERM stdbuf -oL libinput debug-events --device /dev/input/${d%%/*}); " +
      "  fi; " +
      "done; echo 'no touchpad found' >&2; exit 1"]
    stdout: SplitParser {
      onRead: function(line) { root.readSwipe(line) }
    }
    stderr: SplitParser {
      onRead: function(line) { console.warn("swipe-switcher: touchpad reader: " + line) }
    }
    onExited: {
      root.quickFailures = Date.now() - root.touchpadStarted < 60000 ? root.quickFailures + 1 : 0
      if (root.quickFailures < root.maxQuickFailures) touchpadRetry.start()
      else console.warn("swipe-switcher: touchpad reader keeps failing; giving up until the shell restarts")
    }
  }

  Timer {
    id: touchpadRetry
    interval: 30000
    onTriggered: touchpadProc.running = true
  }

  ShellIpc {
    target: "io.github.vekhyat.swipe-switcher"

    function next(): void { root.step(1) }
    function prev(): void { root.step(-1) }
  }

  GlobalShortcut {
    appid: "swipe-switcher"
    name: "next"
    description: "Window switcher: next window"
    onPressed: root.keyStep(1)
  }

  GlobalShortcut {
    appid: "swipe-switcher"
    name: "prev"
    description: "Window switcher: previous window"
    onPressed: root.keyStep(-1)
  }

  GlobalShortcut {
    appid: "swipe-switcher"
    name: "pick"
    description: "Window switcher: pick the highlighted window (Alt released)"
    onPressed: if (root.held && root.mode === "keys") root.release()
  }

  component PlainText: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    elide: Text.ElideRight
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "swipe-switcher"

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: tiles.implicitWidth + root.gap * 2
      height: tiles.implicitHeight + root.gap * 2
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Component.onCompleted: forceActiveFocus()

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) root.cancel()
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.commit()
          else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) { root.step(1) }
          else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) { root.step(-1) }
          else return
          event.accepted = true
        }

        // Backup for the Alt release bind, once the switcher has focus.
        Keys.onReleased: function(event) {
          if (event.key === Qt.Key_Alt && root.held && root.mode === "keys") root.release()
        }
      }

      Row {
        id: tiles
        anchors.centerIn: parent
        spacing: root.gap

        Repeater {
          model: root.windows

          Rectangle {
            id: tile
            required property var modelData
            required property int index
            readonly property bool selected: index === root.selectedIndex

            width: root.tileWidth
            height: header.height + root.previewHeight + root.gap * 1.5
            radius: root.cornerRadius
            color: selected ? root.selectedBackground : "transparent"
            border.width: selected ? Math.max(2, Style.space(2)) : 0
            border.color: root.accent

            Row {
              id: header
              x: root.gap / 2
              y: root.gap / 2
              width: parent.width - root.gap
              spacing: Style.space(6)

              Image {
                id: icon
                width: Style.font.iconLarge
                height: width
                sourceSize: Qt.size(width * 2, height * 2)
                source: root.iconFor(tile.modelData.appId)
                anchors.verticalCenter: parent.verticalCenter
              }

              PlainText {
                width: header.width - icon.width - header.spacing
                text: tile.modelData.title
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            // Sized by constraintSize, so the window keeps its aspect ratio.
            Item {
              id: previewBox
              x: root.gap / 2
              y: header.y + header.height + root.gap / 2
              width: parent.width - root.gap
              height: root.previewHeight

              ScreencopyView {
                id: shot
                anchors.centerIn: parent
                captureSource: tile.modelData.toplevel
                live: true
                constraintSize: Qt.size(previewBox.width, previewBox.height)
                // Wait a moment so the cached frame is a painted one.
                onHasContentChanged: if (hasContent) rememberTimer.start()
              }

              Timer {
                id: rememberTimer
                interval: 150
                onTriggered: if (shot.hasContent) root.remember(tile.modelData.address, shot)
              }

              // No live frame: the last one we saw, or failing that the icon.
              Image {
                readonly property var snapshot: root.snapshots[tile.modelData.address]
                visible: !shot.hasContent
                anchors.centerIn: parent
                width: snapshot ? parent.width : parent.height / 2
                height: snapshot ? parent.height : parent.height / 2
                fillMode: Image.PreserveAspectFit
                sourceSize: snapshot ? undefined : Qt.size(width * 2, height * 2)
                source: snapshot ? snapshot.url : root.iconFor(tile.modelData.appId)
              }
            }

            // Click only: selecting on hover would let a resting pointer
            // override the swipe.
            MouseArea {
              anchors.fill: parent
              onClicked: { root.selectedIndex = tile.index; root.commit() }
            }
          }
        }
      }
    }
  }
}
