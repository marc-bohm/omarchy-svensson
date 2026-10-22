import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The Volvo in the bar: dim when idle, headlights flashing while the phone
// rings, lit with a running call timer while connected.
//   left   = call card while ringing/in a call, phone app otherwise
//   right  = answer / hang up
//   middle = hang up
BarWidget {
  id: root
  moduleName: "marc-bohm.svensson"

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("marc-bohm.svensson") : null
  readonly property bool available: svc ? svc.available : false
  readonly property bool ringing: svc ? svc.ringing : false
  readonly property bool inCall: svc ? svc.inCall : false
  readonly property string callState: svc ? svc.callState : "offline"
  readonly property bool showOffline: setting("showWhenOffline", false) === true

  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color hot: Color.bar.active
  property real flash: 0

  readonly property string timerText: svc && callState === "active" ? svc.elapsedText : ""
  readonly property string tooltip: {
    if (!svc) return "Svensson"
    if (!available) return svc.t("bar.offline")
    if (ringing) return svc.t("bar.ringing", svc.callerLabel(svc.currentCall))
    if (inCall) return svc.t("bar.inCall", svc.stateLabel, svc.callerLabel(svc.currentCall) || svc.lastCaller)
    return svc.t("bar.idle", svc.deviceName)
  }

  visible: available || showOffline || ringing || inCall
  implicitWidth: visible ? row.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  // "Lichthupe" while ringing: two quick flashes, then a pause
  SequentialAnimation {
    running: root.ringing
    loops: Animation.Infinite
    onStopped: root.flash = 0
    NumberAnimation { target: root; property: "flash"; to: 1; duration: 80 }
    NumberAnimation { target: root; property: "flash"; to: 0; duration: 200 }
    NumberAnimation { target: root; property: "flash"; to: 1; duration: 80 }
    NumberAnimation { target: root; property: "flash"; to: 0; duration: 360 }
    PauseAnimation { duration: 700 }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    VolvoArt {
      id: badge
      mini: true
      pixel: root.vertical ? 1 : Math.max(1, Math.round(Style.space(2)))
      anchors.verticalCenter: parent.verticalCenter
      bodyColor: root.ringing
        ? Qt.tint(root.fg, Util.alpha(root.hot, root.flash))
        : (root.inCall ? root.fg : Util.alpha(root.fg, root.available ? 0.7 : 0.35))
      stripColor: Util.alpha(root.fg, 0.35)
      lightColor: Color.accent
      tailColor: Color.urgent
      lightsOn: root.inCall || (root.ringing && root.flash > 0.5)
    }

    Text {
      id: timer
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.vertical && root.timerText !== ""
      textFormat: Text.PlainText
      text: root.timerText
      color: root.fg
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (!root.svc) return
      if (mouse.button === Qt.RightButton) {
        root.svc.toggle()
      } else if (mouse.button === Qt.MiddleButton) {
        if (root.ringing || root.inCall) root.svc.hangup()
      } else if (root.ringing || root.inCall) {
        root.svc.openCall()
      } else {
        root.svc.openDialer("")
      }
    }

    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltip)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
