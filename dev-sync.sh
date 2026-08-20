#!/bin/bash
# Sync plugin files into the omarchy plugins dir. Writing real files there
# (not a symlink) lets the shell's inotify watcher trigger a full hot reload
# including the QML component cache clear.
set -e
src="$(cd "$(dirname "$0")" && pwd)"
dst="$HOME/.config/omarchy/plugins/seb-krz.omarchy-connect"
mkdir -p "$dst"
cp "$src"/manifest.json "$src"/Panel.qml "$src"/Service.qml "$src"/Dbus.qml "$src"/Model.js "$src"/README.md "$src"/LICENSE "$dst"/
