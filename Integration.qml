import QtQuick
import Quickshell.Io

// Desktop integration, installed once per session, independently of the panel
// being open. KDE Connect's own "Explore device" button opens a
// kdeconnect://<device-id>/ URL and expects a KIO file manager to translate
// the virtual root. Omarchy ships Nautilus, which has no KIO, so that URL has
// no handler at all and the button silently does nothing.
//
// This component registers bin/kdeconnect-open as the kdeconnect:// handler,
// which opens the device's real storage in the default file manager. It is
// idempotent and best-effort: a failure here never affects the panel, and
// `bin/kdeconnect-install install|uninstall` can be run by hand.
Item {
  id: root

  // Directory this plugin was loaded from, without a trailing slash. Used to
  // reach the bundled scripts regardless of where the plugin was installed.
  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    if (url.indexOf("file://") === 0) url = url.substring(7)
    try { url = decodeURIComponent(url) } catch (e) { url = url }
    while (url.length > 1 && url.charAt(url.length - 1) === "/")
      url = url.substring(0, url.length - 1)
    return url
  }

  readonly property string handlerPath: pluginDir + "/bin/kdeconnect-open"

  property bool installed: false

  Process {
    id: installer
    command: [root.pluginDir + "/bin/kdeconnect-install", "install"]
    // Missing interpreter, no xdg-mime, ... must not surface in the UI.
    onExited: function (exitCode) { root.installed = exitCode === 0 }
  }

  Component.onCompleted: installer.running = true
}
