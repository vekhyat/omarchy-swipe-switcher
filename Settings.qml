import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings window. Reads and changes the settings held by this plugin's
// service (Switcher.qml), which applies them at once and saves them.
// Open it with `omarchy-shell shell toggle io.github.vekhyat.swipe-switcher`.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  // This plugin's running service (Switcher.qml), handed in by the shell.
  property var service: null
  readonly property var settings: root.service ? root.service.settings : ({})

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color accent: Commons.Color.accent
  property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int pad: Style.spacing.panelPadding
  property int rowGap: Style.space(14)
  property int cardWidth: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.vekhyat.swipe-switcher")
  }

  function set(key, value) {
    if (root.service) root.service.setSetting(key, value)
  }

  // Before the catalog loads, t() returns the key, which has no %1 to fill.
  function withNumber(key, value) {
    var text = strings.t(key)
    var number = Commons.I18n.formatNumber(value, 0)
    return text.indexOf("%1") >= 0 ? text.arg(number) : number
  }

  function statusText() {
    var status = root.service ? root.service.readerStatus : ""
    return status ? strings.t("status." + status) : ""
  }

  // The Alt+Tab bind lines from the README, for the clipboard.
  readonly property string altTabSnippet:
    "local function alt_tab(forward)\n" +
    "  return function()\n" +
    "    local window = hl.get_active_window()\n" +
    "    if window and (window.fullscreen or 0) >= 2 then\n" +
    "      hl.dispatch(hl.dsp.global(forward and \"swipe-switcher:next\" or \"swipe-switcher:prev\"))\n" +
    "    else\n" +
    "      hl.dispatch(hl.dsp.window.cycle_next({ next = forward }))\n" +
    "      hl.dispatch(hl.dsp.window.bring_to_top())\n" +
    "    end\n" +
    "  end\n" +
    "end\n" +
    "hl.unbind(\"ALT + TAB\")\n" +
    "hl.unbind(\"ALT + SHIFT + TAB\")\n" +
    "o.bind(\"ALT + TAB\", \"Next window\", alt_tab(true), { repeating = true })\n" +
    "o.bind(\"ALT + SHIFT + TAB\", \"Previous window\", alt_tab(false), { repeating = true })\n" +
    "o.bind(\"Alt_L\", \"Window switcher: pick\", hl.dsp.global(\"swipe-switcher:pick\"),\n" +
    "  { release = true, transparent = true, ignore_mods = true, non_consuming = true })\n"
  property bool copied: false

  component Label: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    wrapMode: Text.WordWrap
  }

  component Caption: Label {
    color: root.muted
    font.pixelSize: Style.font.caption
  }

  component Slider: Item {
    id: sliderRow
    property string label: ""
    property string valueText: ""
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property real stepSize: 1
    signal changed(real value)

    width: parent.width
    height: sliderLabel.height + Style.space(6) + slider.height

    Label {
      id: sliderLabel
      text: sliderRow.label
      width: parent.width - sliderValue.width
    }
    Label {
      id: sliderValue
      anchors.right: parent.right
      text: sliderRow.valueText
      color: root.accent
    }
    PanelSlider {
      id: slider
      y: sliderLabel.height + Style.space(6)
      width: parent.width
      height: Style.space(22)
      value: sliderRow.value
      minimum: sliderRow.minimum
      maximum: sliderRow.maximum
      step: sliderRow.stepSize
      integer: true
      trackColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
      fillColor: root.accent
      knobColor: root.foreground
      onMoved: function(v) { sliderRow.changed(v) }
    }
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "swipe-switcher-settings"

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(content.implicitHeight + root.pad * 2, panel.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          }
        }
      }

      Flickable {
        anchors.fill: parent
        anchors.margins: root.pad
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: parent.width
          spacing: root.rowGap

          Label {
            text: strings.t("title")
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          PanelSectionHeader { text: strings.t("section.swipe"); foreground: root.muted }

          Toggle {
            width: parent.width
            label: strings.t("swipe.enabled")
            description: root.statusText()
            checked: !!root.settings.swipeEnabled
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: root.set("swipeEnabled", !root.settings.swipeEnabled)
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            opacity: root.settings.swipeEnabled ? 1 : 0.45
            enabled: !!root.settings.swipeEnabled
            Label { text: strings.t("swipe.fingers") }
            ButtonGroup {
              options: [{ value: "3", label: "3" }, { value: "4", label: "4" }]
              value: String(root.settings.swipeFingers || 3)
              foreground: root.foreground
              background: root.background
              accent: root.accent
              fontFamily: root.fontFamily
              onChanged: function(v) { root.set("swipeFingers", parseInt(v)) }
            }
            Caption { width: parent.width; text: strings.t("swipe.fingers.hint") }
          }

          Slider {
            opacity: root.settings.swipeEnabled ? 1 : 0.45
            enabled: !!root.settings.swipeEnabled
            label: strings.t("swipe.distance")
            // Shown as sensitivity: less travel per window feels faster.
            valueText: root.withNumber("swipe.distance.value", root.settings.stepDistance || 105)
            value: root.settings.stepDistance || 105
            minimum: 30
            maximum: 300
            stepSize: 5
            onChanged: function(v) { root.set("stepDistance", Math.round(v)) }
          }
          Caption {
            width: parent.width
            text: strings.t("swipe.distance.hint")
          }

          Toggle {
            width: parent.width
            enabled: !!root.settings.swipeEnabled
            opacity: root.settings.swipeEnabled ? 1 : 0.45
            label: strings.t("swipe.reverse")
            description: strings.t("swipe.reverse.hint")
            checked: !!root.settings.reverseSwipe
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: root.set("reverseSwipe", !root.settings.reverseSwipe)
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            Label { text: strings.t("swipe.order") }
            ButtonGroup {
              options: [
                { value: "position", label: strings.t("swipe.order.position") },
                { value: "recent", label: strings.t("swipe.order.recent") }
              ]
              value: root.settings.swipeOrder || "position"
              foreground: root.foreground
              background: root.background
              accent: root.accent
              fontFamily: root.fontFamily
              onChanged: function(v) { root.set("swipeOrder", v) }
            }
          }

          Toggle {
            width: parent.width
            label: strings.t("swipe.wrap")
            description: strings.t("swipe.wrap.hint")
            checked: !!root.settings.wrapSwipe
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: root.set("wrapSwipe", !root.settings.wrapSwipe)
          }

          PanelSectionHeader { text: strings.t("section.previews"); foreground: root.muted }

          Slider {
            label: strings.t("previews.height")
            valueText: root.withNumber("previews.height.value", root.settings.previewHeight || 170)
            value: root.settings.previewHeight || 170
            minimum: 80
            maximum: 360
            stepSize: 10
            onChanged: function(v) { root.set("previewHeight", Math.round(v)) }
          }

          PanelSectionHeader { text: strings.t("section.alttab"); foreground: root.muted }

          Caption { width: parent.width; text: strings.t("alttab.hint") }

          Row {
            spacing: Style.space(10)
            Button {
              text: root.copied ? strings.t("alttab.copied") : strings.t("alttab.copy")
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                Quickshell.clipboardText = root.altTabSnippet
                root.copied = true
                copiedTimer.restart()
              }
            }
          }

          Timer {
            id: copiedTimer
            interval: 2000
            onTriggered: root.copied = false
          }

          Row {
            spacing: Style.space(10)
            Button {
              text: strings.t("reset")
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.resetSettings()
            }
            Button {
              text: strings.t("close")
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.dismiss()
            }
          }
        }
      }
    }
  }
}
