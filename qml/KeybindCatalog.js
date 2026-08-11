// Curated action catalogs for the Keybind Manager panel.
//
// These lists must stay in sync with the whitelists in scripts/apply.sh --
// the panel only ever sends values from here, and the script rejects
// anything else. No free-form shell commands pass through.

const Launches = [
  { value: "terminal", label: "Terminal" },
  { value: "browser", label: "Browser" },
  { value: "editor", label: "Editor" },
  { value: "file-manager", label: "File manager" },
  { value: "file-manager-cwd", label: "File manager (cwd)" },
  { value: "spotify", label: "Spotify" },
  { value: "terminal-tmux", label: "Tmux" },
  { value: "floating-terminal-presentation", label: "Floating presentation terminal" },
  { value: "config-editor", label: "Config editor" },
  { value: "about", label: "About" },
  { value: "screensaver", label: "Screensaver" },
];

const Commands = [
  { value: "screenshot", label: "Screenshot" },
  { value: "screenshot-region", label: "Screenshot region" },
  { value: "screenrecording", label: "Screen recording" },
  { value: "color-picker", label: "Color picker" },
  { value: "lock", label: "Lock screen" },
  { value: "clipboard-manager", label: "Clipboard manager" },
  { value: "emoji-picker", label: "Emoji picker" },
  { value: "apps-menu", label: "Apps menu" },
  { value: "root-menu", label: "Omarchy root menu" },
  { value: "keybindings-menu", label: "Keybindings menu" },
];

function _workspaceDispatchers() {
  const list = [];
  for (let i = 1; i <= 10; i++) {
    list.push({ value: "workspace." + i, label: "Switch to workspace " + i });
  }
  return list;
}

const Dispatchers = [
  { value: "window.close", label: "Close window" },
  { value: "window.kill", label: "Kill window" },
  { value: "window.fullscreen", label: "Toggle fullscreen" },
  { value: "window.float", label: "Toggle floating / tiling" },
  { value: "window.pin", label: "Pin window (float & pin)" },
  { value: "group.toggle", label: "Toggle window group" },
  { value: "focus.next", label: "Next workspace" },
  { value: "focus.prev", label: "Previous workspace" },
].concat(_workspaceDispatchers());

const Kinds = [
  { value: "launch", label: "Launch app" },
  { value: "webapp", label: "Web app" },
  { value: "command", label: "System action" },
  { value: "dispatcher", label: "Window / workspace" },
  { value: "disable", label: "Unbind default" },
];

function optionsFor(kind) {
  switch (kind) {
    case "launch": return Launches;
    case "command": return Commands;
    case "dispatcher": return Dispatchers;
    default: return [];
  }
}

function labelFor(list, value) {
  for (const item of list) {
    if (item.value === value) return item.label;
  }
  return value;
}

function kindLabel(kind) {
  return labelFor(Kinds, kind);
}

function actionLabel(kind, value) {
  switch (kind) {
    case "launch": return labelFor(Launches, value);
    case "command": return labelFor(Commands, value);
    case "dispatcher": return labelFor(Dispatchers, value);
    case "webapp": return "Web app: " + value;
    default: return "";
  }
}

function badgeLabel(entry) {
  if (!entry) return "Added";
  if (entry.kind === "disable") return "Default disabled";
  if (entry.replaces) return "Overrides \u201c" + entry.replaces + "\u201d";
  return "Added";
}

module.exports = {
  Launches: Launches,
  Commands: Commands,
  Dispatchers: Dispatchers,
  Kinds: Kinds,
  optionsFor: optionsFor,
  actionLabel: actionLabel,
  kindLabel: kindLabel,
  badgeLabel: badgeLabel,
};
