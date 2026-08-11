#!/bin/bash
# Keybind Manager -- mutation engine.
#
# Owns the plugin's persistent state (keybinds.json) and rewrites the managed
# block inside ~/.config/hypr/bindings.lua. Every mutation:
#
#   1. snapshots bindings.lua to a single rolling .bak file
#   2. rewrites only the marker-delimited managed block
#   3. reloads Hyprland and reports `hyprctl configerrors`
#
# Only the block between the begin/end markers is ever touched, so the user's
# hand-written lines are preserved. All values are validated against curated
# whitelists -- the QML side may not pass free-form shell commands through.

set -euo pipefail

PLUGIN_ID="dev.deoxizn.keybind-manager"
PLUGIN_NAME="Keybind Manager"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="$CONFIG_HOME/omarchy/keybind-manager"
STATE_FILE="$STATE_DIR/keybinds.json"
BINDINGS_FILE="$CONFIG_HOME/hypr/bindings.lua"
BACKUP_FILE="${BINDINGS_FILE}.bak"

BEGIN_MARKER="-- >>> keybind-manager begin (managed by dev.deoxizn.keybind-manager; edit the plugin, not this block)"
END_MARKER="-- <<< keybind-manager end"

# ---------------------------------------------------------------------------
# Curated catalogs (the only values accepted for each kind).
# ---------------------------------------------------------------------------

LAUNCH_PRESETS="
terminal
browser
editor
file-manager
file-manager-cwd
spotify
terminal-tmux
floating-terminal-presentation
config-editor
about
screensaver
"

COMMAND_PRESETS="
screenshot
screenshot-region
screenrecording
color-picker
lock
clipboard-manager
emoji-picker
apps-menu
root-menu
keybindings-menu
"

DISPATCHER_PRESETS="
window.close
window.kill
window.fullscreen
window.float
window.pin
group.toggle
focus.next
focus.prev
workspace.1
workspace.2
workspace.3
workspace.4
workspace.5
workspace.6
workspace.7
workspace.8
workspace.9
workspace.10
"

command_string() {
  case "$1" in
    screenshot)            echo "omarchy-capture-screenshot" ;;
    screenshot-region)     echo "omarchy-capture-region" ;;
    screenrecording)       echo "omarchy-capture-screenrecording" ;;
    color-picker)          echo "pkill hyprpicker || hyprpicker -a" ;;
    lock)                  echo "omarchy-system-lock" ;;
    clipboard-manager)     echo "omarchy-menu-clipboard" ;;
    emoji-picker)          echo "omarchy-menu-emoji" ;;
    apps-menu)             echo "omarchy-menu toggle apps" ;;
    root-menu)             echo "omarchy-menu toggle root" ;;
    keybindings-menu)      echo "omarchy-menu-keybindings" ;;
    *) echo "" ;;
  esac
}

dispatcher_expr() {
  case "$1" in
    window.close)   echo "hl.dsp.window.close()" ;;
    window.kill)    echo "hl.dsp.window.kill()" ;;
    window.fullscreen) echo "hl.dsp.window.fullscreen({ action = \"toggle\" })" ;;
    window.float)   echo "hl.dsp.window.float({ action = \"toggle\" })" ;;
    window.pin)     echo "hl.dsp.window.pin({ action = \"toggle\" })" ;;
    group.toggle)   echo "hl.dsp.group.toggle()" ;;
    focus.next)     echo "hl.dsp.focus({ workspace = \"e+1\" })" ;;
    focus.prev)     echo "hl.dsp.focus({ workspace = \"e-1\" })" ;;
    workspace.*)    echo "hl.dsp.focus({ workspace = \"${1#workspace.}\" })" ;;
    *) echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log_err() { echo "ERROR: $*" >&2; }

in_list() {
  local needle="$1" haystack="$2"
  echo "$haystack" | grep -qx "$needle"
}

# Escape a value for inclusion inside a double-quoted Lua string literal.
# Drops control bytes (JSON/terminal junk), keeps UTF-8 text as-is.
lua_escape() {
  printf '%s' "$1" \
    | LC_ALL=C tr -d '\000-\037\177' \
    | LC_ALL=C sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Keys are combos like "SUPER + K" or "XF86AudioRaiseVolume". Restrict to a
# safe charset and reject anything that could break out of a Lua literal.
valid_keys() {
  local value="$1"
  [[ -n "$value" && ${#value} -le 64 ]] || return 1
  LC_ALL=C grep -Eq '^[A-Za-z0-9 +\-_:,]+$' <<<"$value"
}

valid_description() {
  local value="$1"
  [[ -n "$value" ]] || return 1
  # Reject control bytes (newlines, escapes) that could break out of a Lua
  # string literal; jq handles UTF-8 safely and counts characters, not bytes.
  jq -e -n --arg v "$value" \
    '($v | length) <= 80 and (($v | test("[\u0000-\u001f\u007f]")) | not)' \
    >/dev/null 2>&1
}

# Canonical combo form used for equality checks: uppercase, whitespace removed,
# tokens split on '+' and sorted. "SUPER + SHIFT + K" == "super shift+k" etc.
normalize_combo() {
  printf '%s' "$1" \
    | tr '[:lower:]' '[:upper:]' \
    | tr -d '[:space:]' \
    | tr '+' '\n' \
    | sort \
    | paste -sd' ' -
}

# Look up what a key currently does in the live Hyprland config. Returns the
# menu's display description, or nothing when the key is unbound.
detect_default() {
  local wanted norm
  wanted="$1"
  norm="$(normalize_combo "$wanted")"
  [[ -n "$norm" ]] || return 0

  omarchy menu keybindings --print 2>/dev/null | while IFS= read -r line; do
    local combo desc candidate
    combo="${line%% → *}"
    desc="${line#* → }"
    [[ -n "$desc" ]] || continue
    candidate="$(normalize_combo "$combo")"
    if [[ "$candidate" == "$norm" ]]; then
      printf '%s\n' "$desc"
      return 0
    fi
  done
  return 0
}

# Refuse duplicate binds (and duplicate disables) before touching the state.
# selector: "disable" to compare against disables, anything else for binds.
check_duplicate() {
  local keys="$1" selector="$2" norm dup
  norm="$(normalize_combo "$keys")"

  if [[ "$selector" == "disable" ]]; then
    dup="$(jq -r --arg norm "$norm" '
      [.entries[] | select(.kind == "disable")
       | (.keys | ascii_upcase | gsub("[[:space:]]"; "") | split("+") | sort | join(" "))
      ] | any(. == $norm)' "$STATE_FILE")"
  else
    dup="$(jq -r --arg norm "$norm" '
      [.entries[] | select(.kind != "disable")
       | (.keys | ascii_upcase | gsub("[[:space:]]"; "") | split("+") | sort | join(" "))
      ] | any(. == $norm)' "$STATE_FILE")"
  fi

  [[ "$dup" != "true" ]] || {
    log_err "key already managed: $keys"
    return 1
  }
  return 0
}

valid_url() {
  local value="$1"
  [[ ${#value} -le 256 ]] || return 1
  LC_ALL=C grep -Eq '^https?://[A-Za-z0-9./?&=_%:#~@+-]+$' <<<"$value"
}

init_state() {
  mkdir -p "$STATE_DIR"
  if [[ ! -f "$STATE_FILE" ]]; then
    printf '{"version":1,"entries":[]}\n' > "$STATE_FILE"
  fi
}

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

render_block() {
  init_state
  local entries
  entries=$(jq -c '.entries // []' "$STATE_FILE" 2>/dev/null || printf '[]')

  printf '%s\n' "$BEGIN_MARKER"

  jq -r '.[] | select(.kind == "disable") | [.keys, (.description // "")] | @tsv' \
      <<<"$entries" | while IFS=$'\t' read -r keys desc; do
    printf -- '-- disabled by %s: %s\n' "$PLUGIN_NAME" "$(lua_escape "$desc")"
    printf 'hl.unbind("%s")\n' "$(lua_escape "$keys")"
  done

  jq -r '.[] | select(.kind != "disable")
         | [.keys, .description, .kind, (.value // ""), (.replaces // "")]
         | @tsv' <<<"$entries" | while IFS=$'\t' read -r keys desc kind value replaces; do
    if [[ -n "$replaces" ]]; then
      printf -- '-- overriding default: %s\n' "$(lua_escape "$replaces")"
      printf 'hl.unbind("%s")\n' "$(lua_escape "$keys")"
    fi

    case "$kind" in
      launch)
        printf 'o.bind("%s", "%s", { omarchy = "%s" })\n' \
          "$(lua_escape "$keys")" "$(lua_escape "$desc")" "$(lua_escape "$value")"
        ;;
      webapp)
        printf 'o.bind("%s", "%s", { webapp = "%s" })\n' \
          "$(lua_escape "$keys")" "$(lua_escape "$desc")" "$(lua_escape "$value")"
        ;;
      command)
        printf 'o.bind("%s", "%s", "%s")\n' \
          "$(lua_escape "$keys")" "$(lua_escape "$desc")" \
          "$(lua_escape "$(command_string "$value")")"
        ;;
      dispatcher)
        printf 'o.bind("%s", "%s", %s)\n' \
          "$(lua_escape "$keys")" "$(lua_escape "$desc")" "$(dispatcher_expr "$value")"
        ;;
    esac
  done

  printf '%s\n' "$END_MARKER"
}

# ---------------------------------------------------------------------------
# State mutations
# ---------------------------------------------------------------------------

add_entry() {
  local keys="" desc="" kind="" value="" replaces=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --replaces) replaces="${2:-}"; shift 2 ;;
      *) 
        if [[ -z "$keys" ]]; then keys="$1"
        elif [[ -z "$desc" ]]; then desc="$1"
        elif [[ -z "$kind" ]]; then kind="$1"
        elif [[ -z "$value" ]]; then value="$1"
        fi
        shift ;;
    esac
  done

  valid_keys "$keys" || { log_err "invalid keys '$keys'"; return 1; }
  valid_description "$desc" || { log_err "invalid description"; return 1; }

  case "$kind" in
    launch)
      in_list "$value" "$LAUNCH_PRESETS" || { log_err "unknown launch preset '$value'"; return 1; }
      ;;
    webapp)
      valid_url "$value" || { log_err "invalid webapp url"; return 1; }
      ;;
    command)
      in_list "$value" "$COMMAND_PRESETS" || { log_err "unknown command preset '$value'"; return 1; }
      ;;
    dispatcher)
      in_list "$value" "$DISPATCHER_PRESETS" || { log_err "unknown dispatcher '$value'"; return 1; }
      ;;
    *)
      log_err "unknown kind '$kind'"; return 1 ;;
  esac

  [[ -z "$replaces" ]] && replaces=""
  valid_description "$replaces" 2>/dev/null || replaces=""

  init_state
  check_duplicate "$keys" bind || return 1

  [[ -n "$replaces" ]] || replaces="$(detect_default "$keys")"
  valid_description "$replaces" 2>/dev/null || replaces=""

  jq --arg keys "$keys" --arg desc "$desc" --arg kind "$kind" \
     --arg value "$value" --arg replaces "$replaces" \
     '.entries += [{
        "id": ("kbm-" + ((now * 1000) | floor | tostring)),
        "keys": $keys,
        "description": $desc,
        "kind": $kind,
        "value": $value,
        "replaces": $replaces,
        "created": (now | strftime("%Y-%m-%dT%H:%M:%S"))
     }]' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

  apply_block
}

disable_entry() {
  local keys="$1" desc="${2:-}"
  valid_keys "$keys" || { log_err "invalid keys '$keys'"; return 1; }
  [[ -z "$desc" ]] && desc="(default binding)"
  valid_description "$desc" || desc="(default binding)"

  init_state
  check_duplicate "$keys" disable || return 1

  jq --arg keys "$keys" --arg desc "$desc" \
     '.entries += [{
        "id": ("kbd-" + ((now * 1000) | floor | tostring)),
        "keys": $keys,
        "description": $desc,
        "kind": "disable",
        "value": "",
        "replaces": "",
        "created": (now | strftime("%Y-%m-%dT%H:%M:%S"))
     }]' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

  apply_block
}

remove_entry() {
  local id="$1"
  [[ -n "$id" ]] || { log_err "missing id"; return 1; }

  init_state
  jq --arg id "$id" '.entries |= map(select(.id != $id))' "$STATE_FILE" \
    > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

  apply_block
}

# ---------------------------------------------------------------------------
# bindings.lua rewrite
# ---------------------------------------------------------------------------

strip_managed_block() {
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { inblock = 1; next }
    $0 == end   { inblock = 0; next }
    !inblock    { print }
  ' "$1"
}

# Drop trailing blank lines so repeated applies don't grow whitespace.
trim_trailing_blanks() {
  awk '{ lines[NR] = $0 } END {
    while (NR > 0 && lines[NR] == "") NR--
    for (i = 1; i <= NR; i++) print lines[i]
  }'
}

apply_block() {
  if [[ ! -f "$BINDINGS_FILE" ]]; then
    log_err "hypr bindings file not found: $BINDINGS_FILE"
    return 1
  fi

  # Single rolling backup of the pre-change file.
  cp -f "$BINDINGS_FILE" "$BACKUP_FILE"

  local block
  block="$(render_block)"

  strip_managed_block "$BINDINGS_FILE" | trim_trailing_blanks > "$BINDINGS_FILE.tmp"

  {
    cat "$BINDINGS_FILE.tmp"
    printf '\n%s\n\n' "$block"
  } > "$BINDINGS_FILE"
  rm -f "$BINDINGS_FILE.tmp"

  reload_and_validate
}

reload_and_validate() {
  hyprctl reload >/dev/null 2>&1 || true

  local errors
  errors="$(hyprctl configerrors 2>&1 || true)"

  case "$errors" in
    "" | "No config errors found." | "0 config errors found." | *"0 errors"*)
      printf 'OK: keybindings applied, config clean (backup at %s)\n' "$BACKUP_FILE"
      return 0
      ;;
  esac

  printf 'WARNING: config errors reported after apply:\n%s\n' "$errors"
  return 2
}

revert_backup() {
  if [[ ! -f "$BACKUP_FILE" ]]; then
    log_err "no backup to restore ($BACKUP_FILE)"
    return 1
  fi
  cp -f "$BACKUP_FILE" "$BINDINGS_FILE"
  hyprctl reload >/dev/null 2>&1 || true
  printf 'OK: restored previous bindings.lua from %s\n' "$BACKUP_FILE"
}

# ---------------------------------------------------------------------------
# CLI dispatch
# ---------------------------------------------------------------------------

case "${1:-list}" in
  list)
    init_state
    cat "$STATE_FILE"
    ;;
  render)
    render_block
    ;;
  add)
    shift
    add_entry "$@"
    ;;
  disable)
    shift
    disable_entry "$1" "${2:-}"
    ;;
  detect)
    shift
    detect_default "$1"
    ;;
  remove | reenable)
    shift
    remove_entry "$1"
    ;;
  apply)
    apply_block
    ;;
  revert)
    revert_backup
    ;;
  reset)
    init_state
    printf '{"version":1,"entries":[]}\n' > "$STATE_FILE"
    apply_block
    ;;
  *)
    log_err "unknown command '$1'"
    exit 2
    ;;
esac
