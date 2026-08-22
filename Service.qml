import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Owns all KDE Connect state: lifecycle, snapshot orchestration, debounced
// event reconciliation, primary-device selection. UI reads properties and
// calls the public methods; it never sees D-Bus output.
Item {
  id: root

  // ---- public state ----
  property bool cliInstalled: false
  property string backendState: Model.BackendState.Unknown
  property bool refreshing: false
  property var devices: []
  property string preferredDeviceId: ""
  property string lastActiveDeviceId: ""
  readonly property string primaryDeviceId: Model.selectPrimaryId(devices, preferredDeviceId, lastActiveDeviceId)
  readonly property var primaryDevice: {
    for (var i = 0; i < devices.length; i++)
      if (devices[i].id === primaryDeviceId) return devices[i]
    return null
  }
  readonly property bool monitorActive: dbus.monitorActive
  property double lastRefreshMs: 0

  signal stateUpdated()
  signal refreshed()
  // A file finished landing on disk. path/name are device-controlled display
  // strings: never executed, never used to build a command.
  signal fileReceived(string path, string name)

  function debugJson() {
    return Model.snapshotSummary(backendState, devices)
  }

  // ---- refresh orchestration ----
  property bool _pendingRefresh: false
  property var _monitorFilter: Model.makeMonitorFilter()

  readonly property var _busctl: ["busctl", "--user", "--timeout=3"]

  function _daemonCall(member, extra) {
    return _busctl.concat(["call", "org.kde.kdeconnect", "/modules/kdeconnect",
      "org.kde.kdeconnect.daemon", member]).concat(extra || []).concat(["--json=short"])
  }

  function _devicePath(id) { return "/modules/kdeconnect/devices/" + id }

  function _getAll(path, iface) {
    return _busctl.concat(["call", "org.kde.kdeconnect", path,
      "org.freedesktop.DBus.Properties", "GetAll", "s", iface, "--json=short"])
  }

  function _deviceCall(id, member, extra) {
    return _busctl.concat(["call", "org.kde.kdeconnect", _devicePath(id),
      "org.kde.kdeconnect.device", member]).concat(extra || []).concat(["--json=short"])
  }

  // KDE Connect opens its own configured destination; nothing is passed in.
  function openReceivedFolder(id) {
    if (!id) return
    dbus.call(_busctl.concat(["call", "org.kde.kdeconnect", _devicePath(id) + "/share",
      "org.kde.kdeconnect.device.share", "openDestinationFolder"]))
  }

  function refresh() {
    if (refreshing) { _pendingRefresh = true; return }
    refreshing = true
    dbus.call(_daemonCall("devices", ["bb", "false", "false"]), function (out) {
      var ids = Model.parseDeviceIds(out)
      if (ids === null) {
        _applyBackendDown()
        return
      }
      _collectDevices(ids, [])
    })
  }

  function _collectDevices(ids, acc) {
    if (ids.length === 0) { _applySnapshot(acc); return }
    var id = ids[0]
    var rest = ids.slice(1)
    dbus.call(_getAll(_devicePath(id), "org.kde.kdeconnect.device"), function (propsOut) {
      var props = Model.parseProperties(propsOut)
      if (props === null) {
        // Device vanished mid-snapshot — skip it, keep the rest.
        _collectDevices(rest, acc)
        return
      }
      dbus.call(_deviceCall(id, "loadedPlugins"), function (loadedOut) {
        var loaded = Model.parseStringList(loadedOut)
        var hasBattery = loaded !== null && loaded.indexOf("kdeconnect_battery") !== -1
        if (!hasBattery) {
          acc.push(Model.normalizeDevice(id, props, loaded, null))
          _collectDevices(rest, acc)
          return
        }
        dbus.call(_getAll(_devicePath(id) + "/battery", "org.kde.kdeconnect.device.battery"), function (batOut) {
          // Battery failure must never fail the device (optional capability).
          acc.push(Model.normalizeDevice(id, props, loaded, Model.parseProperties(batOut)))
          _collectDevices(rest, acc)
        })
      })
    })
  }

  function _applySnapshot(list) {
    var ordered = Model.orderDevices(list)
    // Track "most recently active": a device that just became connected.
    for (var i = 0; i < ordered.length; i++) {
      var now = ordered[i]
      if (!now.connected) continue
      var was = null
      for (var j = 0; j < devices.length; j++)
        if (devices[j].id === now.id) { was = devices[j]; break }
      if (!was || !was.connected) lastActiveDeviceId = now.id
    }
    var changed = !Model.snapshotEquals(ordered, devices)
    if (changed) devices = ordered
    if (backendState !== Model.BackendState.Ready) {
      backendState = Model.BackendState.Ready
      changed = true
    }
    lastRefreshMs = Date.now()
    if (changed) stateUpdated()
    _endRefresh()
  }

  function _applyBackendDown() {
    var next = cliInstalled ? Model.BackendState.NoDaemon : Model.BackendState.NotInstalled
    var changed = backendState !== next || devices.length > 0
    backendState = next
    if (devices.length > 0) devices = []
    if (changed) stateUpdated()
    _endRefresh()
  }

  function _endRefresh() {
    refreshing = false
    refreshed()
    if (_pendingRefresh) {
      _pendingRefresh = false
      Qt.callLater(refresh)
    }
  }

  // ---- actions ----
  // One action at a time; UI shows transient status then auto-clears.
  property var action: ({ kind: "", deviceId: "", status: "idle" })

  function ring(id) { _cliAction("ring", id, ["kdeconnect-cli", "--ring", "--device", id]) }
  function ping(id) { _cliAction("ping", id, ["kdeconnect-cli", "--ping", "--device", id]) }
  function sendClipboard(id) { _cliAction("clipboard", id, ["kdeconnect-cli", "--send-clipboard", "--device", id]) }
  // text is user input passed as a single argv element — never a shell string.
  function shareText(id, text) { _cliAction("sharetext", id, ["kdeconnect-cli", "--share-text", text, "--device", id]) }

  function rediscover() {
    dbus.call(_daemonCall("forceOnNetworkChange"), function () { refresh() })
  }

  // Pairing goes straight to the device D-Bus interface.
  function requestPairing(id) { _pairCall(id, "requestPairing") }
  function acceptPairing(id) { _pairCall(id, "acceptPairing") }
  function cancelPairing(id) { _pairCall(id, "cancelPairing") }
  function unpair(id) { _pairCall(id, "unpair") }

  function _pairCall(id, member) {
    dbus.call(_deviceCall(id, member), function () { refresh() })
  }

  function _cliAction(kind, id, argv) {
    if (action.status === "running") return
    action = { kind: kind, deviceId: id, status: "running" }
    actionTimeout.restart()
    actionProc.command = argv
    actionProc.running = true
  }

  Process {
    id: actionProc
    onExited: function (exitCode) {
      actionTimeout.stop()
      root.action = Object.assign({}, root.action, { status: exitCode === 0 ? "success" : "failed" })
      actionClear.restart()
      root.refresh()
    }
  }

  // A hung action is killed rather than leaving a busy UI; kill path flows
  // through onExited with a nonzero code → "failed".
  Timer {
    id: actionTimeout
    interval: 10000
    onTriggered: actionProc.running = false
  }

  Timer {
    id: actionClear
    interval: 2500
    onTriggered: root.action = { kind: "", deviceId: "", status: "idle" }
  }

  // ---- event-driven invalidation ----
  Connections {
    target: dbus
    function onMonitorLine(line) {
      if (root._monitorFilter.feed(line)) debounceTimer.restart()
      var share = root._monitorFilter.takeShare()
      if (share) root.fileReceived(share, Model.baseName(share))
    }
    function onMonitorActiveChanged() {
      // Fresh parser state per monitor process; lines don't span restarts.
      if (dbus.monitorActive) root._monitorFilter = Model.makeMonitorFilter()
    }
  }

  Timer {
    id: debounceTimer
    interval: 200
    onTriggered: root.refresh()
  }

  // Slow reconciliation: recovery only, not normal operation.
  Timer {
    interval: 45000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: whichCli
    command: ["which", "kdeconnect-cli"]
    onExited: function (exitCode) {
      root.cliInstalled = exitCode === 0
      root.refresh()
    }
  }

  Dbus { id: dbus }

  Component.onCompleted: {
    whichCli.running = true
    dbus.startMonitor()
  }
}
