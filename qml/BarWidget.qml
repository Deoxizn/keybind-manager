pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar button for Keybind Manager and host for the keybind panel. Shows a
// keyboard glyph; left click toggles the panel.
//
// Theming: colors and sizes come from the active bar. A Shibumi bar hands us
// its VisualTokens (bar.visualTokens); any other host is covered by HostTokens,
// which derives the same interface from the bar's standard properties.
BarWidget {
  id: root
  moduleName: "dev.deoxizn.keybind-manager"

  readonly property string serviceId: "dev.deoxizn.keybind-manager"
  property var service: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(serviceId) : null

  // ---- Service acquisition. The shell ensures the service at startup, but
  //      the widget can mount while it's still loading. `serviceFor` is a
  //      function call, so the binding above won't re-evaluate on its own —
  //      re-query on a short timer until the service exists.
  property bool serviceClaimed: false
  property int serviceTries: 0

  function tryClaimService() {
    if (!root.serviceClaimed && root.bar && root.bar.shell
        && typeof root.bar.shell.serviceFor === "function") {
      var svc = root.bar.shell.serviceFor(root.serviceId)
      if (svc !== root.service) root.service = svc
      if (svc) {
        root.serviceClaimed = true
        root.serviceTries = 0
        serviceRetry.stop()
        root.injectPanel()
        return
      }
    }
    if (!root.serviceClaimed && root.serviceTries < 60) {
      root.serviceTries++
      serviceRetry.restart()
    }
  }

  onServiceChanged: tryClaimService()
  Component.onCompleted: tryClaimService()
  Component.onDestruction: serviceRetry.stop()

  Timer {
    id: serviceRetry
    interval: 250
    onTriggered: root.tryClaimService()
  }

  HostTokens {
    id: hostTokens
    bar: root.bar
  }

  // Prefer the bar's own tokens (Shibumi VisualTokens) so per-widget color
  // fills configured in Shibumi settings keep working; fall back to the
  // built-in adapter for the stock bar and other Quattro hosts.
  readonly property var tokens: bar && "visualTokens" in bar && bar.visualTokens
    ? bar.visualTokens : hostTokens

  readonly property bool pillActive: service ? service.busy : false
  readonly property string pillTooltip: service
    ? (service.entries.length + " custom keybind" + (service.entries.length === 1 ? "" : "s") + " \u2014 click to manage")
    : "Keybindings"

  // ---- Popup contract. Bar.findPanelWidget requires open/close/opened on
  //      the widget root; the popout coordinator compares against the slot's
  //      activeItem, which is this widget.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property real openPanelIndicatorWidth: Math.max(
    Style.space(10), pill.labelWidth)
  readonly property real openPanelIndicatorHeight: Math.max(
    Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("service" in target) target.service = root.service
    if ("tokens" in target) target.tokens = root.tokens
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = pill
    if ("hostWidget" in target) target.hostWidget = root
  }

  visible: true
  implicitWidth: visible ? pill.implicitWidth : 0
  implicitHeight: visible ? pill.implicitHeight : 0

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onTokensChanged: injectPanel()

  KeybindPill {
    id: pill
    bar: root.bar
    tokens: root.tokens
    active: root.pillActive
    tooltipText: root.pillTooltip
    onPressed: function(button) {
      if (button === Qt.LeftButton) root.togglePanel()
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("KeybindPanel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
}
