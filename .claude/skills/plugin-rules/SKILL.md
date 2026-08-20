---
name: plugin-rules
description: Hard rules from DesignDocument.md for writing Omarchy Connect plugin code. Invoke before writing or reviewing any QML or JS for this plugin — covers security requirements, module boundaries, architecture constraints, and theming.
---

# Omarchy Connect implementation rules

Distilled from DesignDocument.md; section references point there for full context. When a rule seems to conflict with what you're building, read the referenced section before deviating.

## Security (§25 — mandatory, plugin runs unsandboxed inside omarchy-shell)

1. Never construct shell commands with string concatenation; every `Process` uses an argv array.
2. Never use `bash -c` with device-controlled values.
3. Device names and remote-command names are untrusted display strings — never executed, never used to build commands.
4. Never request sudo, never touch firewall config, never install packages (the "not installed" panel offers **Copy command**, not Install).
5. Never log clipboard, notification, or SMS content; don't persist verification keys unnecessarily.
6. Every operation that can stall gets a timeout; a malformed device response must not crash `omarchy-shell`.

## Architecture

- **D-Bus for state, `kdeconnect-cli` for actions.** Never parse CLI output for state (§ADR, ~line 439).
- **Event invalidation, not signal parsing (ADR-004):** the bus monitor never decodes payloads — any relevant signal triggers a debounced (150–250 ms) full snapshot reconcile. A slow 30–60 s timer is recovery only. Never poll `kdeconnect-cli` on a timer.
- **Capability-driven UI (§~607):** derive available actions from KDE Connect's loaded/supported plugin lists, never from `device.type == "phone"`.
- **Battery is optional (§~646):** battery failure never fails the device as a whole; introspect the installed API rather than assuming paths.
- **Multi-device from day one (ADR-005):** "first device returned" must never appear in the model; primary-device selection follows the 6-level precedence at §~266. Persist the preferred device ID, never dynamic connection state.
- **Distinguish failure states (§24):** package missing / D-Bus service down / daemon starting / no devices / devices unreachable — never collapse into "Disconnected".
- **Hot-reload safety (§~954):** don't rebuild QML list models when normalized state is unchanged.

## Module boundaries (§35)

- `Dbus.qml` — transport only: D-Bus commands, monitor lifecycle, raw responses, transport errors.
- `Model.js` — parsing, normalization, equality, device ordering, capability maps.
- `Service.qml` — lifecycle, state, action orchestration, retries, selection, timers, public methods.
- `Panel.qml` — presentation only: bar icon, panel, selection interaction.

Don't prematurely split into many small components (§~960).

## Theming (§~1028)

- No hard-coded palette: all colors, spacing, radii, font sizes derive from Omarchy's semantic theme tokens. No KDE blue branding, no custom shadow system.
- Nerd Font icon idiom; no emoji.
