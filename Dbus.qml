import QtQuick
import Quickshell.Io

// Transport only: serial busctl call queue + persistent bus monitor.
// No parsing here — raw text goes up, argv arrays come down (never shell
// strings; device-derived values are only ever single argv elements).
Item {
  id: root

  signal monitorLine(string line)

  readonly property bool monitorActive: monitorProc.running
  property int callTimeoutMs: 5000

  property var _queue: []
  property var _current: null

  function call(argv, cb) {
    _queue.push({ argv: argv, cb: cb })
    _next()
  }

  function startMonitor() {
    restartTimer.stop()
    monitorProc.running = true
  }

  function _next() {
    if (_current || _queue.length === 0) return
    _current = _queue.shift()
    callProc.command = _current.argv
    callTimer.restart()
    callWatchdog.restart()
    callProc.running = true
  }

  function _finish(text) {
    if (!_current) return
    callTimer.stop()
    callWatchdog.stop()
    var cb = _current.cb
    _current = null
    if (cb) cb(text)
    _next()
  }

  Process {
    id: callProc
    stdout: StdioCollector {
      waitForEnd: true
      // Sole delivery path. Killing the process closes the stream, so this
      // also fires on timeout kills — never deliver from onExited as well:
      // a late exited handler can hand call A's output to call B's callback.
      onStreamFinished: root._finish(text)
    }
  }

  Timer {
    id: callTimer
    interval: root.callTimeoutMs
    onTriggered: callProc.running = false
  }

  // If a call never delivers (spawn failure, lost stream), unstick the queue.
  // Restarted per call, stopped on delivery — cannot fire across calls.
  Timer {
    id: callWatchdog
    interval: 15000
    onTriggered: root._finish("")
  }

  // Persistent monitor. Every line is forwarded; the owner decides relevance.
  // Restarts with backoff on death, backoff resets after 30s of health.
  property int _backoffIndex: 0
  readonly property var _backoffs: [1000, 2000, 5000, 10000]

  Process {
    id: monitorProc
    command: ["busctl", "--user", "monitor", "org.kde.kdeconnect"]
    stdout: SplitParser {
      onRead: function (segment) { root.monitorLine(segment) }
    }
    onExited: {
      restartTimer.interval = root._backoffs[Math.min(root._backoffIndex, root._backoffs.length - 1)]
      root._backoffIndex = root._backoffIndex + 1
      restartTimer.start()
    }
  }

  Timer {
    id: restartTimer
    onTriggered: monitorProc.running = true
  }

  Timer {
    interval: 30000
    running: monitorProc.running
    onTriggered: root._backoffIndex = 0
  }
}
