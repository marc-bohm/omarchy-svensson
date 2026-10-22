import QtQuick
import Quickshell
import Quickshell.Io

// Headless state for the Svensson plugin.
//   - `bin/svensson watch` streams phone/call state JSON from PipeWire's
//     Bluetooth telephony service (HFP).
//   - `bin/svensson-contacts sync` pulls phonebook + call history over
//     PBAP (bluez-obex) into ~/.cache/svensson/contacts.json.
// The bar widget and the panel only read from here and call its actions.
Item {
  id: root

  property var shell: null
  property var manifest: null
  // Injected by the shell host on service creation; must stay writable
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "marc-bohm.svensson"
  readonly property string pluginDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir).replace(/\/$/, "")
    : Quickshell.env("HOME") + "/.config/omarchy/plugins/marc-bohm.svensson"
  readonly property string tool: pluginDir + "/bin/svensson"
  readonly property string contactsTool: pluginDir + "/bin/svensson-contacts"
  readonly property string reconnectTool: pluginDir + "/bin/svensson-reconnect"
  readonly property string routeTool: pluginDir + "/bin/svensson-route"
  readonly property string heroImage: "file://" + pluginDir + "/assets/volvo-960.png"
  readonly property string headlightImage: "file://" + pluginDir + "/assets/headlights.png"
  readonly property string cacheFile: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/svensson/contacts.json"

  // ------------------------------------------------------------ call state

  property var status: ({ available: false, service: false, state: "offline", calls: [] })

  readonly property bool available: status.available === true
  readonly property string callState: status.state || "offline"
  readonly property string deviceName: status.device || "iPhone"
  readonly property var calls: status.calls || []
  readonly property var currentCall: pickCall(calls)
  readonly property bool ringing: callState === "incoming"
  readonly property bool inCall: ["active", "dialing", "alerting", "held"].indexOf(callState) !== -1
  readonly property bool busy: ringing || inCall

  // Survive the call so the panel can say who just hung up
  property string lastCaller: ""
  property string lastCallerPhoto: ""
  property bool justEnded: false
  property bool rejectedLocally: false
  // Set when the call was answered or dialled from this PC. Only then may we
  // pull the audio over — if the call was picked up on the phone itself,
  // grabbing the transport would yank it out of the user's ear mid-sentence.
  property bool startedLocally: false
  property string lastDialed: ""

  property double activeSince: 0
  property int elapsed: 0
  readonly property string elapsedText: formatDuration(elapsed)

  readonly property string stateLabel: {
    switch (callState) {
    case "incoming": return "Eingehender Anruf"
    case "dialing": return "Wählt …"
    case "alerting": return "Klingelt …"
    case "active": return "Verbunden · " + elapsedText
    case "held": return "Gehalten"
    case "idle": return justEnded ? "Aufgelegt" : "Bereit"
    default: return "Kein iPhone verbunden"
    }
  }

  // -------------------------------------------------------------- contacts

  property var phonebook: ({ contacts: [], calls: [], syncedAt: 0 })
  readonly property var contacts: phonebook.contacts || []
  readonly property var recentCalls: phonebook.calls || []
  readonly property int syncedAt: phonebook.syncedAt || 0
  readonly property var numberIndex: buildIndex(contacts)
  property bool syncing: false
  property string syncMessage: ""
  property string syncError: ""

  function numberKey(number) {
    var digits = String(number || "").replace(/\D/g, "")
    return digits.length >= 6 ? digits.slice(-9) : digits
  }

  function buildIndex(list) {
    var index = ({})
    for (var i = 0; i < list.length; i++) {
      var numbers = list[i].numbers || []
      for (var j = 0; j < numbers.length; j++) {
        var key = numberKey(numbers[j].number)
        if (key && !index[key]) index[key] = list[i]
      }
    }
    return index
  }

  function contactFor(number) {
    return numberIndex[numberKey(number)] || null
  }

  function callerLabel(call) {
    if (!call) return ""
    var contact = contactFor(call.number)
    return (contact && contact.name) || call.name || formatNumber(call.number) || "Unbekannte Nummer"
  }

  function callerPhoto(call) {
    var contact = call ? contactFor(call.number) : null
    return contact && contact.photo ? "file://" + contact.photo : ""
  }

  function initials(name) {
    var words = String(name || "").trim().split(/\s+/).filter(function(w) {
      return w.charAt(0).toLowerCase() !== w.charAt(0).toUpperCase()
    })
    if (words.length === 0) return "#"
    return (words[0].charAt(0) + (words.length > 1 ? words[words.length - 1].charAt(0) : "")).toUpperCase()
  }

  function parsePhonebook(text) {
    try {
      var data = JSON.parse(text || "{}")
      if (data && Array.isArray(data.contacts)) phonebook = data
    } catch (e) {}
  }

  function syncContacts() {
    if (syncing || !available || demo) return false
    syncing = true
    syncError = ""
    syncMessage = "Synchronisiere …"
    syncer.running = true
    return true
  }

  function syncedLabel() {
    if (syncing) return "Synchronisiere mit " + deviceName + " …"
    if (syncError) return contacts.length > 0 ? contacts.length + " Kontakte · " + syncError : syncError
    if (!syncedAt) return "Noch nicht synchronisiert"
    var minutes = Math.floor((Date.now() / 1000 - syncedAt) / 60)
    var ago = minutes < 1 ? "gerade eben" : minutes < 60 ? "vor " + minutes + " Min" : minutes < 1440 ? "vor " + Math.floor(minutes / 60) + " Std" : "vor " + Math.floor(minutes / 1440) + " Tagen"
    return contacts.length + " Kontakte · " + ago
  }

  // --------------------------------------------------------------- helpers

  function pickCall(list) {
    var order = ["incoming", "waiting", "active", "alerting", "dialing", "held"]
    for (var i = 0; i < order.length; i++) {
      for (var j = 0; j < list.length; j++) {
        if (list[j] && list[j].state === order[i]) return list[j]
      }
    }
    return null
  }

  function formatNumber(number) {
    var n = String(number || "")
    // German mobile numbers get "+49 1xx xxxxxxx" grouping (prefixes are
    // always 1xx); landline area codes vary in length, so only split the
    // country code off those and leave anything else untouched.
    var m = n.match(/^(?:\+49|0049)(1\d{2})(\d{4,})$/)
    if (m) return "+49 " + m[1] + " " + m[2]
    m = n.match(/^0(1\d{2})(\d{4,})$/)
    if (m) return "0" + m[1] + " " + m[2]
    m = n.match(/^\+49(\d+)$/)
    if (m) return "+49 " + m[1]
    return n
  }

  function formatDuration(seconds) {
    var s = Math.max(0, seconds | 0)
    var h = Math.floor(s / 3600)
    var mm = Math.floor((s % 3600) / 60)
    var ss = s % 60
    var pad = function(v) { return v < 10 ? "0" + v : String(v) }
    return (h > 0 ? h + ":" + pad(mm) : pad(mm)) + ":" + pad(ss)
  }

  function formatWhen(iso) {
    var d = new Date(iso)
    if (isNaN(d.getTime())) return ""
    var now = new Date()
    var pad = function(v) { return v < 10 ? "0" + v : String(v) }
    var time = pad(d.getHours()) + ":" + pad(d.getMinutes())
    var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    if (d.getTime() >= startOfToday) return time
    if (d.getTime() >= startOfToday - 86400000) return "Gestern " + time
    return pad(d.getDate()) + "." + pad(d.getMonth() + 1) + ". " + time
  }

  // ---------------------------------------------------------------- ingest

  property string lastLine: ""
  property bool alive: true

  Component.onDestruction: {
    root.alive = false
    restartTimer.stop()
    watcher.running = false
  }

  function ingest(line) {
    if (!line || line === lastLine) return
    lastLine = line
    var next
    try { next = JSON.parse(line) } catch (e) { return }
    if (!next || typeof next !== "object") return

    var prev = callState
    var prevCall = currentCall
    var wasAvailable = available
    status = next
    var now = callState

    var wasDemo = demo
    if (next.ag !== "demo") demo = false

    if (currentCall) {
      lastCaller = callerLabel(currentCall)
      lastCallerPhoto = callerPhoto(currentCall)
    }

    if (available && !wasAvailable && !demo && Date.now() / 1000 - syncedAt > 6 * 3600)
      autoSyncTimer.restart()

    if (now === prev) return

    if (prev === "incoming" && (now === "idle" || now === "offline") && !rejectedLocally && !wasDemo)
      notifyMissed(prevCall)
    if (now !== "incoming") rejectedLocally = false

    if (now === "active") {
      activeSince = Date.now()
      elapsed = 0
      // Answering only picks up the call; the audio transport is separate and
      // has to be asked for. The phone needs a moment before it will hand it
      // over, hence the short delay.
      if (startedLocally && !demo) audioTimer.restart()
    }

    if (now === "incoming" || now === "dialing" || now === "alerting") {
      justEnded = false
      endedTimer.stop()
      openCall()
    }

    var wasBusy = ["incoming", "active", "dialing", "alerting", "held"].indexOf(prev) !== -1
    if (wasBusy && (now === "idle" || now === "offline")) {
      startedLocally = false
      audioTimer.stop()
      activeSince = 0
      justEnded = true
      endedTimer.restart()
      // Refresh the call history once the phone has written it
      if (!wasDemo) autoSyncTimer.restart()
    }
  }

  // --------------------------------------------------------------- actions

  function run(args) {
    Quickshell.execDetached([root.tool].concat(args))
  }

  function answer() {
    if (demo) return runDemo("active")
    startedLocally = true
    run(["answer"])
  }

  function hangup() {
    if (demo) return runDemo("off")
    if (ringing) rejectedLocally = true
    run(["hangup"])
  }

  function pullAudio() {
    if (!demo) run(["audio"])
  }

  function dial(number) {
    var n = String(number || "").replace(/[^0-9+*#]/g, "")
    if (!n || !available) return false
    lastDialed = n
    var contact = contactFor(n)
    lastCaller = contact ? contact.name : formatNumber(n)
    lastCallerPhoto = contact && contact.photo ? "file://" + contact.photo : ""
    if (demo) {
      runDemo("dialing", n)
      return true
    }
    startedLocally = true
    run(["dial", n])
    return true
  }

  function notifyMissed(call) {
    var label = callerLabel(call) || "Unbekannte Nummer"
    var args = [omarchyPath + "/bin/omarchy-notification-send", "-g", String.fromCodePoint(0xF03F7),
      "-u", "normal", "Verpasster Anruf", label + " · Klicken zum Zurückrufen"]
    var number = call ? String(call.number || "").replace(/[^0-9+*#]/g, "") : ""
    if (number) args = args.concat(["--exec", root.tool, "dial", number])
    Quickshell.execDetached(args)
  }

  function openCall() {
    if (shell) shell.summon(pluginId, JSON.stringify({ view: "call" }))
  }

  function openDialer(tab) {
    reconnect()
    if (shell) shell.summon(pluginId, JSON.stringify({ view: "dial", tab: tab || "" }))
  }

  function closePanel() {
    if (shell) shell.hide(pluginId)
  }

  function toggle() {
    if (ringing) answer()
    else if (inCall) hangup()
    else openDialer()
  }

  // Fake call states for trying the UI without a real call:
  //   omarchy-shell svensson demo incoming|dialing|alerting|active|held|off
  property bool demo: false

  function runDemo(kind, number) {
    if (kind === "off") {
      if (!demo) return "not in demo"
      // Hang up the fake call, then pull the real state back in
      lastLine = ""
      ingest(JSON.stringify({ available: true, service: true, ag: "demo", address: "", device: deviceName, audio: "idle", state: "idle", calls: [] }))
      refreshTimer.restart()
      return "ok"
    }
    if (["incoming", "dialing", "alerting", "active", "held"].indexOf(kind) === -1)
      return "usage: demo incoming|dialing|alerting|active|held|off"

    // Ring as a real contact when there is one, so the card shows a photo
    var sample = contacts.length > 0 ? contacts[Math.floor(Math.random() * contacts.length)] : null
    var demoNumber = number || (currentCall && demo ? currentCall.number : "")
      || (sample && sample.numbers[0] ? sample.numbers[0].number : "+46701740642")
    demo = true
    lastLine = ""
    ingest(JSON.stringify({
      available: true, service: true, ag: "demo", address: "", device: deviceName, audio: "idle",
      state: kind,
      calls: [{ path: "demo/call1", state: kind, number: demoNumber, name: sample ? "" : "Sven Svensson", incomingLine: "", multiparty: false }]
    }))
    return "ok"
  }

  // ------------------------------------------------------------- processes

  Process {
    id: watcher
    command: [root.tool, "watch"]
    running: true
    stdout: SplitParser {
      onRead: function(data) { root.ingest(data) }
    }
    onExited: function(exitCode, exitStatus) {
      if (!root.alive) return
      root.lastLine = ""
      root.ingest(JSON.stringify({ available: false, service: false, state: "offline", calls: [] }))
      restartTimer.restart()
    }
  }

  Process {
    id: refresher
    command: [root.tool, "status"]
    stdout: SplitParser {
      onRead: function(data) {
        root.lastLine = ""
        root.ingest(data)
      }
    }
  }

  Process {
    id: syncer
    command: [root.contactsTool, "sync"]
    stdout: SplitParser {
      onRead: function(data) {
        try {
          var result = JSON.parse(data)
          root.syncMessage = result.contacts + " Kontakte, " + result.calls + " Anrufe"
          if (result.fetched === 0)
            root.syncError = "iPhone gibt keine Kontakte frei – siehe Hinweis"
        } catch (e) {}
      }
    }
    stderr: SplitParser {
      onRead: function(data) {
        var line = String(data || "")
          .replace(/^svensson-contacts:\s*/, "")
          .replace(/^sync failed:\s*/, "")
        if (!line) return
        // The phone answers an unauthorized phonebook pull with a plain
        // transfer error, so say what that actually means.
        root.syncError = /transfer (error|timed out)/.test(line)
          ? "iPhone gibt das Telefonbuch nicht frei"
          : "Sync fehlgeschlagen: " + line
      }
    }
    onExited: function(exitCode, exitStatus) {
      root.syncing = false
      if (exitCode !== 0 && !root.syncError) root.syncError = "Sync fehlgeschlagen"
      phonebookFile.reload()
    }
  }

  FileView {
    id: phonebookFile
    path: root.cacheFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parsePhonebook(text())
  }

  Timer {
    id: autoSyncTimer
    interval: 6000
    onTriggered: root.syncContacts()
  }

  Timer {
    id: refreshTimer
    interval: 3000
    onTriggered: if (root.alive) refresher.running = true
  }

  Timer {
    id: restartTimer
    interval: 3000
    onTriggered: if (root.alive) watcher.running = true
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.callState === "active"
    triggeredOnStart: true
    onTriggered: root.elapsed = root.activeSince > 0 ? Math.floor((Date.now() - root.activeSince) / 1000) : 0
  }

  Timer {
    id: audioTimer
    interval: 500
    onTriggered: if (root.alive && root.callState === "active") root.pullAudio()
  }

  Timer {
    id: endedTimer
    interval: 2600
    onTriggered: root.justEnded = false
  }

  Process {
    id: router
    command: [root.routeTool]
  }

  // The phone's capture stream would record from the default mic, which has
  // no echo cancelling; svensson-route moves it onto echo_cancel_source. Keep
  // checking for the whole call: the stream only appears once the audio is on
  // the PC, which can be late (or mid-call via the iPhone's audio picker).
  // The script skips streams that are already routed.
  Timer {
    interval: 2000
    repeat: true
    running: root.alive && root.inCall && !root.demo
    triggeredOnStart: true
    onTriggered: if (!router.running) router.running = true
  }

  Process {
    id: reconnector
    command: [root.reconnectTool]
  }

  // BlueZ never re-dials the handsfree profile by itself, so reconnect when
  // the user opens Svensson without a phone. Deliberately no background
  // polling: the iPhone moves its audio to whatever connected last, so nudging
  // it every minute stole playback from other devices in use. The script
  // refuses unless the state is `offline`, so this cannot grab a live call.
  function reconnect() {
    if (!alive || available || demo || reconnector.running) return
    reconnector.running = true
  }

  IpcHandler {
    target: "svensson"

    function status(): string { return JSON.stringify(root.status) }
    function answer(): string { root.answer(); return "ok" }
    function hangup(): string { root.hangup(); return "ok" }
    function toggle(): string { root.toggle(); return "ok" }
    function dial(number: string): string { return root.dial(number) ? "ok" : "invalid" }
    function dialer(): string { root.openDialer(""); return "ok" }
    function contacts(): string { root.openDialer("contacts"); return "ok" }
    function sync(): string { return root.syncContacts() ? "started" : "busy or offline" }
    function demo(kind: string): string { return root.runDemo(kind, "") }
    function ping(): string { return "ok" }
  }
}
