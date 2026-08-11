pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// One process-wide state owner for every Keybind Manager widget instance.
// The shell ensures this service is kept loaded; widgets talk to it through
// bar.shell.serviceFor(). All mutations are delegated to scripts/apply.sh,
// which owns the state file and the bindings.lua rewrite.
Item {
  id: root

  property var manifest: null
  property var shell: null

  readonly property bool ready: true
  readonly property int contractVersion: 1

  readonly property string scriptPath: manifest && manifest.__sourceDir
    ? manifest.__sourceDir + "/scripts/apply.sh" : ""

  // Parsed list of managed entries from keybinds.json. Reassigned on every
  // refresh so Repeater models pick up the change.
  property var entries: []
  property string statusText: "Ready"
  property bool busy: false
  property bool loaded: false

  function refresh(callback) {
    if (root.scriptPath === "") return
    run.listMode = true
    run.command = [root.scriptPath, "list"]
    run.finishCallback = callback || finishRefresh
    run.running = true
  }

  function add(keys, description, kind, value, replaces, callback) {
    var args = [root.scriptPath, "add", keys, description, kind, value]
    if (replaces) { args.push("--replaces"); args.push(replaces) }
    mutate(args, callback)
  }

  function remove(id, callback) {
    mutate([root.scriptPath, "remove", id], callback)
  }

  function disable(keys, description, callback) {
    mutate([root.scriptPath, "disable", keys, description || ""], callback)
  }

  function reenable(id, callback) {
    mutate([root.scriptPath, "reenable", id], callback)
  }

  function reapply(callback) {
    mutate([root.scriptPath, "apply"], callback)
  }

  // Non-mutating read: what the given combo currently does in the live config.
  // Result is passed to the callback as (description). Uses its own Process so
  // it never competes with a running mutation.
  function detect(keys, callback) {
    if (root.scriptPath === "") return
    detector.command = [root.scriptPath, "detect", String(keys || "")]
    detector.finishCallback = callback
    detector.running = true
  }

  function revert(callback) {
    mutate([root.scriptPath, "revert"], callback)
  }

  function mutate(args, callback) {
    if (root.busy || root.scriptPath === "") return false
    root.busy = true
    run.listMode = false
    run.command = args
    run.finishCallback = callback || finishMutation
    run.running = true
    return true
  }

  function finishRefresh(code, output) {
    root.loaded = true
    if (code !== 0) {
      root.statusText = "State read failed"
      return
    }
    try {
      const parsed = JSON.parse(output)
      root.entries = (parsed.entries || []).slice()
      root.statusText = root.entries.length === 0
        ? "No custom keybinds yet"
        : root.entries.length + (root.entries.length === 1 ? " keybind" : " keybinds") + " managed"
    } catch (error) {
      root.statusText = "State parse failed"
    }
  }

  function finishMutation(code, output) {
    const text = String(output || "").replace(/\s+$/, "")
    if (code === 0 && text !== "") root.statusText = text
    else if (code !== 0) root.statusText = "Apply failed (" + code + ")"
    root.refresh()
  }

  function onExited(code) {
    root.busy = false
    const cb = run.finishCallback
    run.finishCallback = null
    if (cb) cb(code, run.resultOutput)
  }

  Process {
    id: run
    property bool listMode: false
    property var finishCallback: null
    property string resultOutput: ""
    property string resultError: ""

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: run.resultOutput = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: run.resultError = String(text || "")
    }
    onExited: root.onExited(code)
  }

  Process {
    id: detector
    property var finishCallback: null
    property string resultOutput: ""

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: detector.resultOutput = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
    }
    onExited: function(code) {
      const cb = detector.finishCallback
      detector.finishCallback = null
      if (cb) cb(code, detector.resultOutput.replace(/\s+$/, ""))
    }
  }

  onScriptPathChanged: if (root.scriptPath !== "") Qt.callLater(function() { root.refresh() })
  Component.onCompleted: if (root.scriptPath !== "") Qt.callLater(function() { root.refresh() })
}
