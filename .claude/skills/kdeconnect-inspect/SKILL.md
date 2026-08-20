---
name: kdeconnect-inspect
description: Inspect and debug KDE Connect state over D-Bus with busctl — list devices, introspect the installed API, read properties, and monitor signals live. Use when developing or debugging the Omarchy Connect backend, checking why a device appears disconnected, or verifying that state changes propagate.
---

# KDE Connect D-Bus inspection

All commands are read-only against the session bus. Verified on this machine: the daemon owns bus names `org.kde.kdeconnect` and `org.kde.kdeconnect.daemon` (same process, `kdeconnectd`).

## Health check first

```bash
busctl --user list --no-pager | grep -i kdeconnect
```

No output → daemon not running (distinguish: package missing vs. service down vs. starting — see DesignDocument.md §24). Start it with `systemctl --user start` only if the user asks.

## Discover devices

```bash
busctl --user tree org.kde.kdeconnect --no-pager
```

Devices live at `/modules/kdeconnect/devices/<device-id>`. Sub-paths under a device (e.g. `.../battery`) are per-plugin objects.

## Introspect — never assume signatures

The design doc (ADR on battery, §"introspect against installed version") forbids baking in method/property signatures from memory. Always introspect the locally installed KDE Connect before calling anything:

```bash
busctl --user introspect org.kde.kdeconnect /modules/kdeconnect --no-pager
busctl --user introspect org.kde.kdeconnect /modules/kdeconnect/devices/<id> --no-pager
```

## Read state

```bash
busctl --user get-property org.kde.kdeconnect /modules/kdeconnect/devices/<id> org.kde.kdeconnect.device <property>
busctl --user call org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon <method> <signature> <args...>
```

Property and method names come from the introspection above, not from memory.

## Monitor signals live

```bash
busctl --user monitor org.kde.kdeconnect
```

Per ADR-004: signal payloads are NOT parsed in the plugin — any relevant signal just means "something changed, take a fresh snapshot" (150–250 ms debounce). Use monitor output only to confirm that toggling phone Wi-Fi / plugging in the charger actually emits signals.

## Actions (not state)

`kdeconnect-cli` is for triggering actions (ring, ping, share) and quick human-readable listings (`kdeconnect-cli -l`). Never parse its output for state — localization and formatting are unstable. Don't pair/unpair/refresh unless the user asked; those have side effects on the phone.
