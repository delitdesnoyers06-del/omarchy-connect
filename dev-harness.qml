// Headless backend harness (DesignDocument.md §36): prints a JSON snapshot on
// every state change so the event path can be proven before any UI exists.
// Must live in the repo root — quickshell only resolves types inside the
// config folder. Run: qs -p dev-harness.qml
import QtQuick
import Quickshell

ShellRoot {
  Service {
    id: svc
    onStateUpdated: console.log("[state]", svc.debugJson())
    onRefreshed: console.log("[refresh] backend=" + svc.backendState
      + " devices=" + svc.devices.length
      + " monitor=" + svc.monitorActive
      + " primary=" + (svc.primaryDeviceId || "none"))
  }
}
