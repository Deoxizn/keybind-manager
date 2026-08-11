pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "KeybindCatalog.js" as Catalog

// Management panel for custom keybindings. Lists every managed entry (custom
// binds and disabled defaults), removes them, and adds new ones through the
// curated action catalog. All mutations are delegated to the plugin service,
// which owns scripts/apply.sh.
Panel {
  id: root
  moduleName: "dev.deoxizn.keybind-manager"
  ipcTarget: ""
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var tokens: null
  readonly property var barIdentity: hostWidget || root

  property var service: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("dev.deoxizn.keybind-manager") : null
  readonly property var entries: service ? service.entries : []

  readonly property color contentForeground: tokens && tokens.ink
    ? tokens.ink : (bar ? bar.foreground : Color.foreground)
  readonly property string contentFontFamily: tokens && tokens.fontFamily
    ? tokens.fontFamily : (bar ? bar.fontFamily : Style.font.family)
  readonly property int labelSize: tokens ? tokens.labelSize : Style.font.body
  readonly property int captionSize: tokens ? tokens.captionSize : Style.font.caption
  readonly property int iconSize: tokens ? tokens.iconSize : Style.space(15)

  readonly property var binds: root.entries.filter(function(e) { return e.kind !== "disable" })
  readonly property var disables: root.entries.filter(function(e) { return e.kind === "disable" })
  readonly property int bindCount: root.binds.length
  readonly property int disableCount: root.disables.length

  readonly property real headerHeight: Style.space(34)
  readonly property real rowHeight: Style.space(46)
  readonly property real rowSpacing: rowHeight + Style.space(2)
  readonly property real sectionHeaderHeight: Style.space(26)
  readonly property real idealHeight: root.headerHeight
    + (root.bindCount > 0 ? root.sectionHeaderHeight + root.bindCount * root.rowSpacing : 0)
    + (root.disableCount > 0 ? root.sectionHeaderHeight + root.disableCount * root.rowSpacing : 0)
    + Style.space(12) + addForm.implicitHeight

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(root.idealHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: addForm.editing
      onMoveRequested: function(dx, dy) { scroll.scrollBy(dy) }
      onActivateRequested: {}
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "d" || t === "D") root.close()
        else if (t === "n" || t === "N") addForm.focusKeys()
      }
    }

    Flickable {
      id: scroll
      anchors.fill: parent
      contentWidth: column.width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      function scrollBy(dy) {
        var delta = Style.space(46)
        scroll.contentY = Math.max(0, Math.min(
          scroll.contentHeight - scroll.height,
          scroll.contentY + dy * delta))
      }

      Column {
        id: column
        width: Math.max(scroll.width, Style.space(300))

        // ---- Header: title, count, close.
        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            text: "KEYBINDS"
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: root.captionSize
            font.letterSpacing: 1
            renderType: Text.NativeRendering
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: root.entries.length + (root.entries.length === 1 ? " entry" : " entries")
            color: Qt.darker(root.contentForeground, 1.9)
            font.family: root.contentFontFamily
            font.pixelSize: root.captionSize
            renderType: Text.NativeRendering
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Item {
              width: Style.space(28)
              height: Style.space(28)
              MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.close()
              }
              IconText {
                anchors.centerIn: parent
                text: "close"
                fill: closeArea.containsMouse ? 1 : 0
                color: root.contentForeground
                font.pixelSize: Style.space(18)
              }
            }
          }
        }

        // ---- Your keybinds.
        SectionHeader {
          width: parent.width
          visible: root.bindCount > 0
          text: "YOUR KEYBINDS"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          captionSize: root.captionSize
        }

        Repeater {
          model: root.binds

          delegate: EntryRow {
            width: column.width
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            labelSize: root.labelSize
            captionSize: root.captionSize
            iconSize: root.iconSize
            mode: "bind"
            onRemove: root.removeEntry(entry)
            onReenable: {}
          }
        }

        Item { width: parent.width; height: root.bindCount > 0 ? Style.space(8) : 0 }

        // ---- Disabled defaults.
        SectionHeader {
          width: parent.width
          visible: root.disableCount > 0
          text: "DISABLED DEFAULTS"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          captionSize: root.captionSize
        }

        Repeater {
          model: root.disables

          delegate: EntryRow {
            width: column.width
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            labelSize: root.labelSize
            captionSize: root.captionSize
            iconSize: root.iconSize
            mode: "disable"
            onRemove: {}
            onReenable: root.reenableEntry(entry)
          }
        }

        Item { width: parent.width; height: Style.space(10) }

        AddForm {
          id: addForm
          width: parent.width
          service: root.service
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          labelSize: root.labelSize
          captionSize: root.captionSize
          iconSize: root.iconSize
        }
      }
    }
  }

  function removeEntry(entry) {
    if (root.service && entry) root.service.remove(entry.id)
  }

  function reenableEntry(entry) {
    if (root.service && entry) root.service.reenable(entry.id)
  }

  component SectionHeader: Item {
    id: section
    property string text: ""
    required property color foreground
    required property string fontFamily
    required property int captionSize

    implicitHeight: root.sectionHeaderHeight
    height: implicitHeight

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: Qt.rgba(section.foreground.r, section.foreground.g,
        section.foreground.b, 0.08)
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      text: section.text
      color: Qt.darker(section.foreground, 1.7)
      font.family: section.fontFamily
      font.pixelSize: section.captionSize
      font.letterSpacing: 1
      renderType: Text.NativeRendering
    }
  }

  component EntryRow: Item {
    id: row
    required property var modelData
    required property int index
    required property color foreground
    required property string fontFamily
    required property int labelSize
    required property int captionSize
    required property int iconSize
    property string mode: "bind"

    readonly property var entry: row.modelData
    readonly property bool isDisable: row.mode === "disable"

    signal remove()
    signal reenable()

    implicitHeight: root.rowHeight
    height: implicitHeight

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: rowHover.containsMouse
        ? Style.hoverFillFor(row.foreground, Color.accent) : "transparent"
    }

    MouseArea {
      id: rowHover
      anchors.fill: parent
      hoverEnabled: true
    }

    // Keys chip.
    Rectangle {
      id: chip
      anchors.left: parent.left
      anchors.leftMargin: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      radius: Style.cornerRadius / 2
      height: Style.space(24)
      width: keysText.implicitWidth + Style.space(14)
      color: Qt.rgba(row.foreground.r, row.foreground.g, row.foreground.b, 0.09)

      Text {
        id: keysText
        anchors.centerIn: parent
        text: row.entry.keys
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: row.captionSize
        font.bold: true
        renderType: Text.NativeRendering
      }
    }

    // Right action button.
    Item {
      id: actionButton
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(28)
      height: Style.space(28)

      MouseArea {
        id: actionArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.isDisable ? row.reenable() : row.remove()
      }
      IconText {
        anchors.centerIn: parent
        text: row.isDisable ? "restore" : "close"
        fill: actionArea.containsMouse ? 1 : 0
        color: Qt.darker(row.foreground, actionArea.containsMouse ? 1.0 : 1.5)
        font.pixelSize: row.iconSize
      }
    }

    // Description + action subline.
    Column {
      anchors.left: chip.right
      anchors.leftMargin: Style.space(12)
      anchors.right: actionButton.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        width: parent.width
        elide: Text.ElideRight
        text: row.entry.description
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: row.labelSize
        renderType: Text.NativeRendering
      }

      Text {
        width: parent.width
        elide: Text.ElideRight
        text: row.isDisable
          ? "Default binding disabled"
          : (row.entry.replaces
              ? "Overrides: \u201c" + row.entry.replaces + "\u201d"
              : Catalog.actionLabel(row.entry.kind, row.entry.value))
        color: Qt.darker(row.foreground, 1.7)
        font.family: row.fontFamily
        font.pixelSize: row.captionSize
        renderType: Text.NativeRendering
      }
    }
  }

  component AddForm: Item {
    id: form

    required property var service
    required property color foreground
    required property string fontFamily
    required property int labelSize
    required property int captionSize
    required property int iconSize

    property string keysText: ""
    property string descText: ""
    property string urlText: ""
    property string kindValue: "launch"
    property string actionValue: "terminal"
    property string detectedText: ""
    property string managedText: ""
    property string statusText: ""

    readonly property real valueRowHeight: Style.space(40)
    readonly property bool editing: keysField.activeFocus || descField.activeFocus
      || urlField.activeFocus || valuePicker.popupOpen
    implicitHeight: column.implicitHeight

    function focusKeys() { keysField.forceActiveFocus() }

    function kindForLabel(label) {
      for (var i = 0; i < Catalog.Kinds.length; i++)
        if (Catalog.Kinds[i].label === label) return Catalog.Kinds[i].value
      return "launch"
    }

    function refreshValuePicker() {
      var options = Catalog.optionsFor(form.kindValue).map(function(o) { return o.value })
      if (options.length > 0) {
        valuePicker.options = options
        valuePicker.value = options.indexOf(form.actionValue) >= 0
          ? form.actionValue : options[0]
      }
    }

    onKindValueChanged: {
      form.actionValue = Catalog.optionsFor(form.kindValue).length > 0
        ? Catalog.optionsFor(form.kindValue)[0].value : ""
      form.refreshValuePicker()
      if (form.kindValue === "disable" && form.descText === "") form.runDetect(true)
    }

    Component.onCompleted: form.refreshValuePicker()

    Timer {
      id: detectTimer
      interval: 450
      repeat: false
      onTriggered: form.runDetect()
    }

    onKeysTextChanged: detectTimer.restart()

    function runDetect(forceFill) {
      var keys = form.keysText.trim()
      if (!keys || !form.service) { form.detectedText = ""; form.managedText = ""; return }

      var owned = managedEntryFor(keys)
      if (owned) {
        form.managedText = "Already managed \u2014 remove it from the list first"
        form.detectedText = ""
        return
      }
      form.managedText = ""

      form.service.detect(keys, function(code, out) {
        if (form.keysText.trim() !== keys) return
        if (code === 0 && out) {
          form.detectedText = form.kindValue === "disable"
            ? "Currently bound to: " + out
            : "Overrides the default: " + out
          if (forceFill && form.kindValue === "disable" && form.descText === "")
            form.descText = out
        } else {
          form.detectedText = ""
        }
      })
    }

    function managedEntryFor(keys) {
      if (!form.service || !form.service.entries) return null
      var norm = normalizeCombo(keys)
      var list = form.service.entries
      for (var i = 0; i < list.length; i++) {
        if (list[i].kind !== "disable" && normalizeCombo(list[i].keys) === norm)
          return list[i]
      }
      return null
    }

    function normalizeCombo(keys) {
      return String(keys).toUpperCase().replace(/\s+/g, "")
        .split("+").filter(function(s) { return s.length > 0 })
        .sort().join(" ")
    }

    function submit() {
      if (!form.service || form.service.busy) return
      var keys = form.keysText.trim()
      var desc = form.descText.trim()

      if (!keys) { form.statusText = "Enter a key combo, e.g. SUPER + K"; return }
      if (!desc) { form.statusText = "Enter a description"; return }

      if (form.kindValue === "disable") {
        form.statusText = "Disabling\u2026"
        form.service.disable(keys, desc, form.finished)
      } else {
        var value = form.kindValue === "webapp" ? form.urlText.trim() : form.actionValue
        if (!value) { form.statusText = "Pick an action"; return }
        form.statusText = "Adding\u2026"
        form.service.add(keys, desc, form.kindValue, value, "", form.finished)
      }
    }

    function finished(code, output) {
      if (code === 0) {
        form.keysText = ""
        form.descText = ""
        form.urlText = ""
        form.detectedText = ""
        form.managedText = ""
        form.statusText = ""
      } else {
        form.statusText = String(output || "Failed (" + code + ")")
      }
    }

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(8)

      SectionHeader {
        width: parent.width
        text: "NEW KEYBIND"
        foreground: form.foreground
        fontFamily: form.fontFamily
        captionSize: form.captionSize
      }

      TextField {
        id: keysField
        width: parent.width
        foreground: form.foreground
        placeholderText: "Keys \u2014 e.g. SUPER + K"
        font.family: form.fontFamily
        onTextChanged: form.keysText = text
        onAccepted: descField.forceActiveFocus()
        Keys.onEscapePressed: keyCatcher.forceActiveFocus()
      }

      TextField {
        id: descField
        width: parent.width
        foreground: form.foreground
        placeholderText: "Description"
        font.family: form.fontFamily
        onTextChanged: form.descText = text
        onAccepted: form.submit()
        Keys.onEscapePressed: keyCatcher.forceActiveFocus()
      }

      ButtonGroup {
        id: kindGroup
        width: parent.width
        options: Catalog.Kinds.map(function(k) { return k.label })
        value: Catalog.Kinds[0].label
        foreground: form.foreground
        fontFamily: form.fontFamily
        fontSize: form.captionSize
        onChanged: form.kindValue = form.kindForLabel(value)
      }

      // Action / value picker row.
      Item {
        width: parent.width
        height: form.valueRowHeight

        Dropdown {
          id: valuePicker
          anchors.left: parent.left
          anchors.right: parent.right
          visible: form.kindValue !== "disable" && form.kindValue !== "webapp"
          foreground: form.foreground
          fontFamily: form.fontFamily
          rowHeight: form.valueRowHeight
          showLabel: false
          onChanged: form.actionValue = value
        }

        TextField {
          id: urlField
          anchors.left: parent.left
          anchors.right: parent.right
          visible: form.kindValue === "webapp"
          foreground: form.foreground
          placeholderText: "https://example.com"
          font.family: form.fontFamily
          onTextChanged: form.urlText = text
          onAccepted: form.submit()
          Keys.onEscapePressed: keyCatcher.forceActiveFocus()
        }
      }

      Text {
        width: parent.width
        visible: form.detectedText !== ""
        text: form.detectedText
        color: Qt.darker(form.foreground, 1.4)
        font.family: form.fontFamily
        font.pixelSize: form.captionSize
        wrapMode: Text.Wrap
        renderType: Text.NativeRendering
      }

      Text {
        width: parent.width
        visible: form.managedText !== ""
        text: form.managedText
        color: Style.selectedStateColor(form.foreground, Color.accent)
        font.family: form.fontFamily
        font.pixelSize: form.captionSize
        wrapMode: Text.Wrap
        renderType: Text.NativeRendering
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Button {
          id: addButton
          text: "Add keybind"
          fontFamily: form.fontFamily
          fontSize: form.labelSize
          foreground: form.foreground
          accent: Color.accent
          bordered: true
          height: Style.space(32)
          width: Style.space(120)
          onClicked: form.submit()
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(0, parent.width - addButton.width - parent.spacing)
          elide: Text.ElideRight
          text: form.statusText
          color: Style.selectedStateColor(form.foreground, Color.accent)
          font.family: form.fontFamily
          font.pixelSize: form.captionSize
          renderType: Text.NativeRendering
        }
      }
    }
  }
}
