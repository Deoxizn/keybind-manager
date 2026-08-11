# Keybind Manager

An Omarchy plugin for turning any key into an action — without editing config
files by hand. Pick a key combo, pick what it does, and it lands in
`~/.config/hypr/bindings.lua` via a managed, marker-delimited block that
survives config updates and shows up in the Omarchy keybindings menu.

## Features

- **Manage from the bar.** A keyboard button on the bar opens a panel listing
  every managed keybind, with remove / re-enable controls and an add form.
- **Curated actions only.** Binds are restricted to launch presets, Omarchy
  system commands, window/workspace dispatchers, and web-app URLs. No free-form
  shell commands are accepted, so nothing can break out of the generated config.
- **Override or disable defaults.** If a key is already bound in the live
  config, the panel tells you what it currently does and the generated block
  unbinds it before binding your action. You can also add "unbind default"
  entries that just remove a stock binding.
- **Config-aware.** Every change snapshots `bindings.lua`, rewrites only the
  managed block, reloads Hyprland, and reports `hyprctl configerrors` back.
  The last pre-change file is kept at `bindings.lua.bak` and can be restored
  with `reset`/`revert` from the CLI.

## Installation

```sh
omarchy plugin add --source git "https://github.com/deoxizn/keybind-manager"
omarchy plugin enable dev.deoxizn.keybind-manager
```

Then add the widget to a bar via **Omarchy → Bar & widgets** (category
*System*, name *Keybind Manager*). The plugin also registers a service, so the
panel stays in sync across every instance.

## Usage

### Add a keybind

1. Click the keyboard icon on the bar (or bind its IPC toggle).
2. Type the keys, e.g. `SUPER + K`.
3. Pick a kind and an action.
4. Click **Add keybind**.

If the combo is already bound, the panel shows what it currently does, and the
entry is recorded as overriding it. Re-adding an already-managed combo is
rejected.

### Unbind a default

Pick **Unbind default** in the add form, enter the keys (the current binding is
auto-detected), and add. The default is removed from the live config while
everything else stays untouched.

### Remove or re-enable

Use the close / restore button on a row.

## Files & layout

```
scripts/apply.sh     mutation engine + CLI (state + bindings.lua rewrite)
qml/BarWidget.qml    bar button + panel host (Shibumi / Quattro compatible)
qml/KeybindPill.qml  the glyph pill
qml/KeybindPanel.qml the management panel
qml/Service.qml      per-process service bridging the panel to apply.sh
qml/KeybindCatalog.js curated action catalog (must match apply.sh whitelists)
qml/HostTokens.qml   color/font adapter for the stock bar and Quattro hosts
```

## CLI

All panel actions go through the same entry point, so scripting is possible:

```sh
apply.sh list                      # dump keybinds.json
apply.sh add "SUPER + K" "Keybindings" command keybindings-menu
apply.sh add "SUPER + RETURN" "Terminal" launch terminal
apply.sh disable "SUPER + SHIFT + S" "Screenshot default"
apply.sh remove <id>               # id from `list`
apply.sh reenable <id>
apply.sh detect "SUPER + K"        # what the key currently does
apply.sh apply                     # rewrite managed block + reload
apply.sh revert                    # restore bindings.lua.bak
apply.sh reset                     # remove all managed entries
```

State lives in `~/.config/omarchy/keybind-manager/keybinds.json`.

## Development

- The service `__sourceDir` is set by the plugin registry, so the scripts path
  resolves wherever the plugin is installed.
- Keep `KeybindCatalog.js` and the `*_PRESETS` in `apply.sh` in sync; the script
  is the source of truth and rejects unknown values.
- The managed block is delimited by the `keybind-manager begin/end` markers;
  `apply.sh` never touches anything outside them.

## License

MIT
