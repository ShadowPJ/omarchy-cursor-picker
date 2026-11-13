import QtQuick
import qs.Commons
import qs.Commons as Commons

// A small labelled button in the panel's style.
Rectangle {
  id: button

  property string label: ""
  signal clicked()

  implicitWidth: text.implicitWidth + Style.spacing.xxl * 2
  implicitHeight: Math.round(36 * Style.fontScale)
  radius: Style.cornerRadius
  color: mouse.containsMouse && button.enabled ? Style.hoverFill : Style.normalFill
  opacity: button.enabled ? 1 : 0.3

  Text {
    id: text
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: button.label
    color: Commons.Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: button.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }
}
