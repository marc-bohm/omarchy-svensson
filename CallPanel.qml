import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Two surfaces share this panel plugin:
//   view "call" — card under the bar with the Volvo 960 hero, caller and
//                 answer/hang-up. Click-through around the card and never
//                 grabs the keyboard, so a ringing phone can't eat typing.
//   view "dial" — the phone app: hero + keypad on the left, contacts and
//                 recent calls on the right. Owns the keyboard: digits dial,
//                 letters search, arrows pick, Enter calls.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "marc-bohm.svensson"
  readonly property var svc: shell ? shell.serviceFor(pluginId) : null

  property bool opened: false
  property string view: "call"
  property string tab: "contacts"
  property string number: ""
  property string query: ""
  property int selected: -1
  property bool pendingDial: false
  property real flashLevel: 0
  property int minuteTick: 0

  readonly property bool available: svc ? svc.available : false
  readonly property string callState: svc ? svc.callState : "offline"
  readonly property bool ringing: svc ? svc.ringing : false
  readonly property bool inCall: svc ? svc.inCall : false
  readonly property bool busy: ringing || inCall
  readonly property string deviceName: svc ? svc.deviceName : "iPhone"
  readonly property var activeCall: svc ? svc.currentCall : null
  readonly property string caller: svc ? (activeCall ? svc.callerLabel(activeCall) : svc.lastCaller) : ""
  readonly property string callerPhoto: svc ? (activeCall ? svc.callerPhoto(activeCall) : svc.lastCallerPhoto) : ""
  readonly property string callerNumber: {
    if (!svc || !activeCall) return ""
    var pretty = svc.formatNumber(activeCall.number)
    return pretty === caller ? "" : pretty
  }
  readonly property string stateLabel: pendingDial && !busy ? "Wählt …" : (svc ? svc.stateLabel : "")
  readonly property real heroGlow: ringing ? flashLevel : (inCall || pendingDial ? 0.42 : 0)

  readonly property color fg: Color.popups.text
  readonly property color muted: Util.alpha(fg, 0.58)
  readonly property color faint: Util.alpha(fg, 0.14)
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color base: Color.background
  readonly property int pad: Style.spacing.panelPadding
  readonly property int gap: Style.spacing.panelGap
  readonly property int edge: Math.max(1, Style.space(2))

  readonly property var contactList: svc ? svc.contacts : []
  readonly property var recentList: svc ? svc.recentCalls : []
  readonly property var listModel: tab === "contacts" ? filterContacts(contactList, query) : filterRecent(recentList, query)
  readonly property string syncLabel: {
    var tick = minuteTick
    return svc ? svc.syncedLabel() : ""
  }

  onListModelChanged: selected = (query !== "" && listModel.length > 0) ? 0 : -1

  // ---------------------------------------------------------------- logic

  function sanitize(text) {
    return String(text || "").replace(/[^0-9+*#]/g, "")
  }

  function filterContacts(list, q) {
    var needle = String(q || "").toLowerCase().trim()
    if (!needle) return list
    var digits = needle.replace(/\D/g, "")
    return list.filter(function(c) {
      if (String(c.name || "").toLowerCase().indexOf(needle) !== -1) return true
      if (!digits) return false
      return (c.numbers || []).some(function(t) { return String(t.number).indexOf(digits) !== -1 })
    })
  }

  function filterRecent(list, q) {
    var needle = String(q || "").toLowerCase().trim()
    if (!needle) return list
    return list.filter(function(c) {
      return String(c.name || "").toLowerCase().indexOf(needle) !== -1 || String(c.number).indexOf(needle) !== -1
    })
  }

  function primaryNumber(contact) {
    var numbers = contact && contact.numbers ? contact.numbers : []
    for (var i = 0; i < numbers.length; i++) if (numbers[i].type === "mobil") return numbers[i].number
    return numbers.length ? numbers[0].number : ""
  }

  function entryNumber(entry) {
    return root.tab === "contacts" ? primaryNumber(entry) : (entry ? entry.number : "")
  }

  function photoUrl(path) {
    return path ? "file://" + path : ""
  }

  function open(payloadJson) {
    var p = ({})
    try { p = JSON.parse(payloadJson || "{}") } catch (e) { p = ({}) }
    if (p.view === "dial" && !root.busy) {
      root.view = "dial"
      root.number = sanitize(p.number)
      root.query = ""
      if (p.tab === "contacts" || p.tab === "recent") root.tab = p.tab
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      root.view = "call"
    }
    root.opened = true
  }

  function close() {
    root.opened = false
    root.pendingDial = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function startDial(n) {
    if (!root.svc || !root.svc.dial(n)) return
    root.number = ""
    root.query = ""
    root.pendingDial = true
    root.view = "call"
    pendingTimer.restart()
  }

  function submit() {
    if (root.selected >= 0 && root.selected < root.listModel.length) {
      startDial(entryNumber(root.listModel[root.selected]))
    } else if (root.number) {
      startDial(root.number)
    } else if (root.svc && root.svc.lastDialed) {
      startDial(root.svc.lastDialed)
    }
  }

  function press(key) {
    if (root.number.length < 32) root.number = root.number + key
  }

  function moveSelection(delta) {
    var count = root.listModel.length
    if (count === 0) return
    root.selected = Math.max(0, Math.min(count - 1, root.selected + delta))
  }

  Connections {
    target: root.svc
    ignoreUnknownSignals: true

    function onCallStateChanged() {
      if (root.busy) {
        root.pendingDial = false
        if (root.view === "dial") root.view = "call"
      }
    }

    function onJustEndedChanged() {
      if (root.svc && !root.svc.justEnded && !root.busy && !root.pendingDial && root.view === "call")
        root.dismiss()
    }
  }

  Timer {
    id: pendingTimer
    interval: 8000
    onTriggered: {
      if (root.pendingDial && !root.busy) root.dismiss()
      root.pendingDial = false
    }
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: root.minuteTick++
  }

  // "Lichthupe": double flash, pause, repeat
  SequentialAnimation {
    running: root.opened && root.ringing
    loops: Animation.Infinite
    NumberAnimation { target: root; property: "flashLevel"; to: 1; duration: 80 }
    NumberAnimation { target: root; property: "flashLevel"; to: 0.08; duration: 200 }
    NumberAnimation { target: root; property: "flashLevel"; to: 1; duration: 80 }
    NumberAnimation { target: root; property: "flashLevel"; to: 0.08; duration: 360 }
    PauseAnimation { duration: 700 }
  }

  FileView {
    id: hostnameFile
    path: "/etc/hostname"
    printErrors: false
  }
  readonly property string hostName: String(hostnameFile.text() || "diesem PC").trim()

  // ------------------------------------------------------ inline components
  // Inline components can't see ids of this file; everything comes in
  // through properties bound at the use site.

  component Caption: Text {
    textFormat: Text.PlainText
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: Style.space(2)
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property color ink: "white"
    property color backdrop: "black"
    signal clicked()
    implicitWidth: chipText.implicitWidth + Style.space(16)
    implicitHeight: chipText.implicitHeight + Style.space(8)
    radius: Style.cornerRadius
    color: Qt.rgba(backdrop.r, backdrop.g, backdrop.b, chipArea.containsMouse ? 0.8 : 0.55)

    Text {
      id: chipText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: chip.label
      color: chip.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: Style.space(1)
    }

    MouseArea {
      id: chipArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  component Avatar: Rectangle {
    id: avatar
    property string photo: ""
    property string label: ""
    property color ink: "white"
    property color edgeColor: "white"
    property int edgeWidth: 2
    color: Qt.rgba(ink.r, ink.g, ink.b, 0.1)
    border.color: edgeColor
    border.width: edgeWidth
    radius: Style.cornerRadius

    Text {
      anchors.centerIn: parent
      visible: picture.status !== Image.Ready
      textFormat: Text.PlainText
      text: avatar.label
      color: avatar.ink
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: Math.max(8, Math.round(avatar.height * 0.36))
    }

    Image {
      id: picture
      anchors.fill: parent
      anchors.margins: avatar.edgeWidth
      source: avatar.photo
      visible: status === Image.Ready
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      sourceSize.width: 160
      sourceSize.height: 160
    }
  }

  component Hero: Item {
    id: hero
    property string source: ""
    property string glowSource: ""
    property real glow: 0
    property bool drift: false
    property color fadeColor: "black"
    property real fadeFrom: 0.35
    clip: true

    Item {
      id: stage
      anchors.fill: parent

      Image {
        anchors.fill: parent
        source: hero.source
        fillMode: Image.PreserveAspectCrop
        verticalAlignment: Image.AlignBottom
        asynchronous: true
        smooth: true
        mipmap: true
      }

      Image {
        anchors.fill: parent
        source: hero.glowSource
        fillMode: Image.PreserveAspectCrop
        verticalAlignment: Image.AlignBottom
        asynchronous: true
        smooth: true
        mipmap: true
        opacity: hero.glow
        visible: opacity > 0.01
      }

      // Slow push-in, like a camera on the car
      SequentialAnimation on scale {
        running: hero.drift && hero.visible
        loops: Animation.Infinite
        NumberAnimation { to: 1.07; duration: 9000; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 9000; easing.type: Easing.InOutSine }
      }
    }

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(hero.fadeColor.r, hero.fadeColor.g, hero.fadeColor.b, 0) }
        GradientStop { position: hero.fadeFrom; color: Qt.rgba(hero.fadeColor.r, hero.fadeColor.g, hero.fadeColor.b, 0) }
        GradientStop { position: 1; color: hero.fadeColor }
      }
    }
  }

  // -------------------------------------------------------------- call card
  PanelWindow {
    id: callWindow
    visible: root.opened && root.view === "call"
    anchors { top: true; left: true; right: true }
    implicitHeight: callCard.y + callCard.height + Style.gapsOut * 2
    color: "transparent"
    WlrLayershell.namespace: "marc-bohm-svensson"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: callCard }

    BorderSurface {
      id: callCard
      width: Math.min(Style.space(480), callWindow.width - Style.gapsOut * 4)
      height: callColumn.implicitHeight + callCard.borderTop + callCard.borderBottom
      anchors.horizontalCenter: parent.horizontalCenter
      // Clear a top bar so the card never covers the clock
      y: (root.shell && root.shell.bar && root.shell.bar.position !== "top" ? 0 : Style.bar.sizeHorizontal) + Style.gapsOut * 2
      radius: Style.cornerRadius
      color: root.base
      borderSpec: Border.surfaceSpec("popups", "border", root.ringing ? root.accent : Color.popups.border, root.edge)

      // Slide down in
      opacity: callWindow.visible ? 1 : 0
      transform: Translate { y: callWindow.visible ? 0 : -Style.space(24); Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } } }
      Behavior on opacity { NumberAnimation { duration: 200 } }

      Column {
        id: callColumn
        x: callCard.borderLeft
        y: callCard.borderTop
        width: callCard.width - callCard.borderLeft - callCard.borderRight
        spacing: root.pad
        bottomPadding: root.pad

        Hero {
          id: callHero
          width: parent.width
          height: Math.round(width * 0.46)
          source: root.svc ? root.svc.heroImage : ""
          glowSource: root.svc ? root.svc.headlightImage : ""
          glow: root.heroGlow
          drift: root.ringing || root.callState === "active"
          fadeColor: root.base
          fadeFrom: 0.72

          Chip {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            label: String.fromCodePoint(0xF03F2) + "  SVENSSON"
            ink: "#ffe9f4"
            backdrop: "#140828"
          }

          Row {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(6)

            Chip {
              label: String.fromCodePoint(0xF00AF) + " " + root.deviceName
              ink: "#ffe9f4"
              backdrop: "#140828"
            }

            Chip {
              label: String.fromCodePoint(0xF0156)
              ink: "#ffe9f4"
              backdrop: "#140828"
              onClicked: root.dismiss()
            }
          }
        }

        Row {
          x: root.pad
          width: parent.width - root.pad * 2
          spacing: Style.space(14)

          Avatar {
            id: callAvatar
            width: Style.space(58)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            photo: root.callerPhoto
            label: root.svc ? root.svc.initials(root.caller) : ""
            ink: root.fg
            edgeColor: root.ringing ? root.accent : root.faint
            edgeWidth: root.edge
            color: Util.alpha(root.fg, 0.06)
          }

          Column {
            width: parent.width - callAvatar.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)

            Caption {
              width: parent.width
              text: root.stateLabel.toUpperCase()
              color: root.ringing ? root.accent : (root.callState === "active" ? root.fg : root.muted)
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.caller || root.deviceName
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.display
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              visible: text !== ""
              textFormat: Text.PlainText
              text: root.callerNumber
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }
        }

        Row {
          id: callActions
          x: root.pad
          width: parent.width - root.pad * 2
          height: visible ? implicitHeight : 0
          spacing: Style.spacing.controlGap
          visible: root.busy || root.pendingDial
          readonly property int buttons: root.ringing || root.inCall ? 2 : 1
          readonly property real cell: (width - spacing * (buttons - 1)) / buttons

          Button {
            width: callActions.cell
            visible: root.ringing
            bordered: true
            selected: true
            text: "Annehmen"
            iconText: String.fromCodePoint(0xF03F2)
            fontSize: Style.font.subtitle
            verticalPadding: Style.space(10)
            foreground: root.accent
            onClicked: if (root.svc) root.svc.answer()
          }

          Button {
            width: callActions.cell
            visible: root.inCall
            bordered: true
            text: "Ton auf PC"
            iconText: String.fromCodePoint(0xF057E)
            fontSize: Style.font.subtitle
            verticalPadding: Style.space(10)
            foreground: root.fg
            onClicked: if (root.svc) root.svc.pullAudio()
          }

          Button {
            width: callActions.cell
            bordered: true
            text: root.ringing ? "Ablehnen" : "Auflegen"
            iconText: String.fromCodePoint(0xF03F5)
            fontSize: Style.font.subtitle
            verticalPadding: Style.space(10)
            foreground: root.urgent
            onClicked: {
              if (root.svc) root.svc.hangup()
              if (root.pendingDial && !root.busy) root.dismiss()
            }
          }
        }
      }
    }
  }

  // -------------------------------------------------------------- phone app
  PanelWindow {
    id: appWindow
    visible: root.opened && root.view === "dial"
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "marc-bohm-svensson-app"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: appCard
      width: Math.min(Style.space(920), appWindow.width - Style.gapsOut * 8)
      height: Math.min(leftPane.implicitHeight + appCard.borderTop + appCard.borderBottom, appWindow.height - Style.gapsOut * 8)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: root.base
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, root.edge)

      scale: appWindow.visible ? 1 : 0.97
      Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

      MouseArea { anchors.fill: parent; onClicked: keyCatcher.forceActiveFocus() }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var k = event.key
          if (k === Qt.Key_Escape) {
            if (root.query) root.query = ""
            else if (root.number) root.number = ""
            else root.dismiss()
          } else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
            root.tab = root.tab === "contacts" ? "recent" : "contacts"
          } else if (k === Qt.Key_Down) {
            root.moveSelection(1)
          } else if (k === Qt.Key_Up) {
            root.moveSelection(-1)
          } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            root.submit()
          } else if (root.query && Util.editsFilter(event, root.query)) {
            root.query = Util.editedFilter(event, root.query)
          } else if (Util.editsFilter(event, root.number)) {
            root.number = root.sanitize(Util.editedFilter(event, root.number))
          } else if (event.matches(StandardKey.Paste)) {
            var pasted = root.sanitize(Quickshell.clipboardText)
            if (pasted) root.number = (root.number + pasted).slice(0, 32)
          } else if (event.text && /^[0-9+*#]$/.test(event.text) && !root.query) {
            root.press(event.text)
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                     && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            root.query = root.query + event.text
          } else {
            return
          }
          event.accepted = true
        }
      }

      Row {
        id: panes
        x: appCard.borderLeft
        y: appCard.borderTop
        width: appCard.width - appCard.borderLeft - appCard.borderRight
        height: appCard.height - appCard.borderTop - appCard.borderBottom

        // ---- left: hero, number, keypad
        Column {
          id: leftPane
          width: Math.round(panes.width * 0.42)
          spacing: root.gap
          bottomPadding: root.pad

          Hero {
            id: appHero
            width: parent.width
            height: Math.round(width * 0.56)
            source: root.svc ? root.svc.heroImage : ""
            glowSource: root.svc ? root.svc.headlightImage : ""
            glow: root.number !== "" ? 0.35 : 0
            drift: appWindow.visible
            fadeColor: root.base
            fadeFrom: 0.72

            Behavior on glow { NumberAnimation { duration: 240 } }

            Chip {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.margins: Style.space(12)
              label: String.fromCodePoint(0xF03F2) + "  SVENSSON"
              ink: "#ffe9f4"
              backdrop: "#140828"
            }

            Chip {
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(12)
              label: String.fromCodePoint(0xF00AF) + " " + (root.available ? root.deviceName : "offline")
              ink: root.available ? "#ffe9f4" : "#ff9aa8"
              backdrop: "#140828"
            }

          }

          Column {
            x: root.pad
            width: parent.width - root.pad * 2
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.number ? (root.svc ? root.svc.formatNumber(root.number) : root.number) : "Nummer"
              color: root.fg
              opacity: root.number ? 1 : 0.35
              font.family: Style.font.family
              font.pixelSize: Style.font.display
              font.bold: true
              elide: Text.ElideLeft
            }

            Caption {
              width: parent.width
              font.bold: false
              font.letterSpacing: 0
              color: root.available ? root.muted : root.urgent
              elide: Text.ElideRight
              text: {
                if (!root.available) return "Kein iPhone verbunden – Bluetooth an?"
                var match = root.number && root.svc ? root.svc.contactFor(root.number) : null
                if (match) return String.fromCodePoint(0xF0004) + " " + match.name
                if (!root.number && root.svc && root.svc.lastDialed) return "Enter wählt " + root.svc.formatNumber(root.svc.lastDialed) + " erneut"
                return "Tippen: Ziffern wählen · Buchstaben suchen"
              }
            }
          }

          Grid {
            id: keypad
            x: root.pad
            width: parent.width - root.pad * 2
            columns: 3
            columnSpacing: Style.spacing.controlGap
            rowSpacing: Style.spacing.controlGap
            readonly property real cell: (width - columnSpacing * 2) / 3

            Repeater {
              model: [
                { key: "1", sub: "" }, { key: "2", sub: "ABC" }, { key: "3", sub: "DEF" },
                { key: "4", sub: "GHI" }, { key: "5", sub: "JKL" }, { key: "6", sub: "MNO" },
                { key: "7", sub: "PQRS" }, { key: "8", sub: "TUV" }, { key: "9", sub: "WXYZ" },
                { key: "*", sub: "" }, { key: "0", sub: "+" }, { key: "#", sub: "" }
              ]

              Button {
                required property var modelData
                width: keypad.cell
                bordered: true
                text: modelData.key + (modelData.sub ? "  " + modelData.sub : "")
                fontSize: Style.font.subtitle
                verticalPadding: Style.space(8)
                foreground: root.fg
                tooltipText: modelData.key === "0" ? "Rechtsklick: +" : ""
                onClicked: root.press(modelData.key)
                onRightClicked: if (modelData.key === "0") root.press("+")
              }
            }
          }

          Row {
            id: dialActions
            x: root.pad
            width: parent.width - root.pad * 2
            spacing: Style.spacing.controlGap

            Button {
              id: backspace
              bordered: true
              iconText: String.fromCodePoint(0xF0B5C)
              verticalPadding: Style.space(10)
              foreground: root.fg
              enabled: root.number !== ""
              opacity: enabled ? 1 : 0.4
              onClicked: root.number = root.number.slice(0, -1)
            }

            Button {
              width: dialActions.width - backspace.width - dialActions.spacing
              bordered: true
              selected: true
              text: "Anrufen"
              iconText: String.fromCodePoint(0xF03F2)
              fontSize: Style.font.subtitle
              verticalPadding: Style.space(10)
              foreground: root.accent
              enabled: root.available && (root.number !== "" || root.selected >= 0 || (root.svc && root.svc.lastDialed !== ""))
              opacity: enabled ? 1 : 0.4
              onClicked: root.submit()
            }
          }
        }

        Rectangle {
          width: root.edge / 2
          height: panes.height
          color: root.faint
        }

        // ---- right: contacts / recent
        Item {
          id: rightPane
          width: panes.width - leftPane.width - root.edge / 2
          height: panes.height

          Row {
            id: tabs
            x: root.pad
            y: root.pad
            spacing: Style.spacing.controlGap

            Button {
              bordered: true
              selected: root.tab === "contacts"
              text: "Kontakte" + (root.contactList.length ? "  " + root.contactList.length : "")
              iconText: String.fromCodePoint(0xF06CB)
              foreground: root.tab === "contacts" ? root.accent : root.fg
              onClicked: root.tab = "contacts"
            }

            Button {
              bordered: true
              selected: root.tab === "recent"
              text: "Anrufe"
              iconText: String.fromCodePoint(0xF02DA)
              foreground: root.tab === "recent" ? root.accent : root.fg
              onClicked: root.tab = "recent"
            }
          }

          Rectangle {
            id: search
            x: root.pad
            y: tabs.y + tabs.height + root.gap
            width: rightPane.width - root.pad * 2
            height: searchText.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: root.query ? Util.alpha(root.accent, 0.1) : "transparent"
            border.color: root.query ? root.accent : root.faint
            border.width: Math.max(1, root.edge / 2)

            Text {
              id: searchText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              textFormat: Text.PlainText
              text: String.fromCodePoint(0xF0349) + "  " + (root.query || "Einfach lostippen zum Suchen …")
              color: root.query ? root.fg : root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }

          ListView {
            id: list
            x: root.pad
            y: search.y + search.height + root.gap
            width: rightPane.width - root.pad * 2
            height: footer.y - y - root.gap
            clip: true
            spacing: Style.space(2)
            model: root.listModel
            currentIndex: root.selected
            boundsBehavior: Flickable.StopAtBounds
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Item {
              id: row
              required property var modelData
              required property int index

              readonly property bool isContact: root.tab === "contacts"
              readonly property bool isSelected: index === root.selected
              readonly property var numbers: isContact ? (modelData.numbers || []) : []
              readonly property string title: isContact ? modelData.name : (modelData.name || (root.svc ? root.svc.formatNumber(modelData.number) : modelData.number))
              readonly property string kindGlyph: modelData.kind === "missed" ? String.fromCodePoint(0xF03FA)
                : modelData.kind === "dialed" ? String.fromCodePoint(0xF03FB) : String.fromCodePoint(0xF03F7)

              width: list.width
              height: rowContent.implicitHeight + Style.space(14)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: row.isSelected ? Util.alpha(root.accent, 0.14) : (rowArea.containsMouse ? Util.alpha(root.fg, 0.05) : "transparent")
                border.color: row.isSelected ? Util.alpha(root.accent, 0.7) : "transparent"
                border.width: Math.max(1, root.edge / 2)
              }

              MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selected = row.index
                  root.startDial(root.entryNumber(row.modelData))
                }
              }

              Row {
                id: rowContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(12)

                Avatar {
                  id: rowAvatar
                  width: Style.space(38)
                  height: width
                  anchors.verticalCenter: parent.verticalCenter
                  photo: root.photoUrl(row.modelData.photo)
                  label: root.svc ? root.svc.initials(row.title) : ""
                  ink: row.isContact || row.modelData.kind !== "missed" ? root.fg : root.urgent
                  edgeColor: row.isSelected ? root.accent : root.faint
                  edgeWidth: Math.max(1, root.edge / 2)
                }

                Column {
                  width: parent.width - rowAvatar.width - trailing.width - parent.spacing * 2
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(3)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: row.title
                    color: !row.isContact && row.modelData.kind === "missed" ? root.urgent : root.fg
                    font.family: Style.font.family
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  // Contacts: one chip per number; recent: time + number
                  Flow {
                    width: parent.width
                    spacing: Style.space(6)
                    visible: row.isContact

                    Repeater {
                      model: row.numbers

                      Text {
                        required property var modelData
                        textFormat: Text.PlainText
                        text: (modelData.type ? modelData.type + " " : "") + (root.svc ? root.svc.formatNumber(modelData.number) : modelData.number)
                        color: numberArea.containsMouse ? root.accent : root.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.underline: numberArea.containsMouse

                        MouseArea {
                          id: numberArea
                          anchors.fill: parent
                          anchors.margins: -Style.space(3)
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.startDial(modelData.number)
                        }
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    visible: !row.isContact
                    textFormat: Text.PlainText
                    text: row.kindGlyph + "  " + (root.svc ? root.svc.formatWhen(row.modelData.when) : "")
                      + (row.modelData.name ? "  ·  " + (root.svc ? root.svc.formatNumber(row.modelData.number) : row.modelData.number) : "")
                    color: row.modelData.kind === "missed" ? root.urgent : root.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Text {
                  id: trailing
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: String.fromCodePoint(0xF03F2)
                  color: row.isSelected || rowArea.containsMouse ? root.accent : root.faint
                  font.family: Style.font.family
                  font.pixelSize: Style.font.iconLarge
                }
              }
            }

            // Empty states
            Column {
              anchors.centerIn: parent
              width: parent.width - Style.space(40)
              spacing: Style.space(10)
              visible: list.count === 0

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: root.query ? String.fromCodePoint(0xF0349) : (root.tab === "contacts" ? String.fromCodePoint(0xF06CB) : String.fromCodePoint(0xF02DA))
                color: root.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.displayLarge * 1.6
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                text: root.query
                  ? "Nichts gefunden für „" + root.query + "“"
                  : (root.tab === "contacts"
                      ? "Noch keine Kontakte.\n\nAm iPhone: Einstellungen → Bluetooth → ⓘ neben „" + root.hostName + "“ → „Kontakte synchronisieren“ einschalten, dann unten auf Sync."
                      : "Noch keine Anrufe synchronisiert.")
              }
            }
          }

          Item {
            id: footer
            x: root.pad
            y: rightPane.height - height - root.pad
            width: rightPane.width - root.pad * 2
            height: syncButton.implicitHeight

            Text {
              anchors.left: parent.left
              anchors.right: syncButton.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.syncLabel
              color: root.svc && root.svc.syncError ? root.urgent : root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Button {
              id: syncButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              bordered: true
              text: "Sync"
              iconText: String.fromCodePoint(0xF04E6)
              iconSpinning: root.svc ? root.svc.syncing : false
              foreground: root.fg
              enabled: root.available && root.svc && !root.svc.syncing
              opacity: enabled ? 1 : 0.5
              onClicked: root.svc.syncContacts()
            }
          }
        }
      }
    }
  }
}
