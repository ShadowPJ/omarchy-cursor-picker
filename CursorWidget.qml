import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// A cursor icon for the bar (or for Den's drawer). Clicking it toggles the
// picker panel, which the plugin's service owns.
BarWidget {
  id: root
  moduleName: "shadowpj.cursorpicker"

  implicitWidth: vertical ? barSize : Style.bar.iconSlot + Style.space(8)
  implicitHeight: vertical ? Style.bar.iconSlot + Style.space(8) : barSize

  // Den (and the bar's panel routing) call toggle() on a widget to open it.
  function toggle() {
    Quickshell.execDetached(["omarchy-shell", "shadowpj.cursorpicker", "panel"])
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰇀"
    tooltipText: "Cursor"
    onPressed: function(b) { root.toggle() }
  }
}
