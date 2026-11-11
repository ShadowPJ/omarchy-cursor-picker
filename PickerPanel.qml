import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "CursorModel.js" as CursorModel

// The picker panel: a searchable grid of installed cursor themes with a
// preview of each arrow, plus a size control. A click applies at once.
OverlayWindow {
  id: window

  property var picker: null

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  WlrLayershell.namespace: "shadowpj-cursorpicker"

  property string query: ""
  readonly property var results: picker ? CursorModel.filter(picker.themes, query) : []

  readonly property int pad: Style.spacing.xxl
  readonly property int cellWidth: Math.round(150 * Style.fontScale)
  readonly property int cellHeight: Math.round(120 * Style.fontScale)

  onShownChanged: {
    if (!shown) return
    window.query = ""
    search.text = ""
    Qt.callLater(function() { search.forceActiveFocus() })
  }

  function close() { window.shown = false }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Commons.Color.background, 0.45)
    MouseArea { anchors.fill: parent; onClicked: window.close() }
  }

  Rectangle {
    id: card
    width: Math.min(parent.width - window.pad * 4, Math.round(720 * Style.fontScale))
    height: Math.min(parent.height - window.pad * 4, Math.round(540 * Style.fontScale))
    anchors.centerIn: parent
    radius: Math.max(Style.cornerRadius, Style.spacing.lg)
    color: Commons.Color.popups.background
    border.width: Style.normalBorderWidth
    border.color: Commons.Color.popups.border

    scale: window.contentRevealed ? 1 : 0.97
    Behavior on scale { NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

    MouseArea { anchors.fill: parent }
    Keys.onEscapePressed: window.close()

    PlainLabel {
      id: title
      x: window.pad
      y: window.pad
      text: strings.t("panel.title")
      font.pixelSize: Style.font.body * 1.3
      font.bold: true
    }

    PlainLabel {
      anchors.left: title.right
      anchors.leftMargin: Style.spacing.lg
      anchors.verticalCenter: title.verticalCenter
      text: strings.tn("panel.count", window.results.length).arg(Commons.I18n.formatNumber(window.results.length))
      opacity: 0.6
    }

    PlainLabel {
      anchors.right: parent.right
      anchors.rightMargin: window.pad
      anchors.verticalCenter: title.verticalCenter
      text: "✕"
      opacity: closeMouse.containsMouse ? 1 : 0.6
      MouseArea {
        id: closeMouse
        anchors.fill: parent
        anchors.margins: -Style.spacing.md
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: window.close()
      }
    }

    TextField {
      id: search
      x: window.pad
      y: title.y + title.height + window.pad
      width: card.width - window.pad * 2
      placeholderText: strings.t("panel.search")
      onTextChanged: window.query = text
      Keys.onEscapePressed: window.close()
      onAccepted: if (window.results.length > 0) window.picker.select(window.results[0].id)
    }

    Rectangle {
      id: gridBox
      x: window.pad
      y: search.y + search.height + Style.spacing.md
      width: card.width - window.pad * 2
      height: sizeRow.y - Style.spacing.md - y
      radius: Style.cornerRadius
      color: Style.normalFill

      PlainLabel {
        visible: window.results.length === 0
        anchors.centerIn: parent
        text: strings.t("panel.none")
        opacity: 0.6
      }

      GridView {
        id: grid
        anchors.fill: parent
        anchors.margins: Style.spacing.sm
        clip: true
        model: window.results
        boundsBehavior: Flickable.StopAtBounds
        cellWidth: Math.floor(width / Math.max(1, Math.floor(width / window.cellWidth)))
        cellHeight: window.cellHeight

        delegate: Item {
          id: cell
          required property var modelData
          readonly property bool active: window.picker && window.picker.current === modelData.id

          width: grid.cellWidth
          height: grid.cellHeight

          Rectangle {
            anchors.fill: parent
            anchors.margins: Style.spacing.xxs
            radius: Style.cornerRadius
            color: cellMouse.containsMouse ? Style.hoverFill : "transparent"
            border.width: cell.active ? Style.normalBorderWidth * 2 : 0
            border.color: Commons.Color.popups.text

            Item {
              id: previewBox
              anchors.top: parent.top
              anchors.topMargin: Style.spacing.lg
              anchors.horizontalCenter: parent.horizontalCenter
              width: Math.round(56 * Style.fontScale)
              height: width

              Image {
                id: preview
                anchors.centerIn: parent
                source: window.picker ? window.picker.previewSource(cell.modelData.id) : ""
                sourceSize: Qt.size(previewBox.width, previewBox.height)
                width: Math.min(implicitWidth, previewBox.width)
                height: Math.min(implicitHeight, previewBox.height)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                cache: false
              }

              PlainLabel {
                visible: preview.status !== Image.Ready
                anchors.centerIn: parent
                text: "↖"
                font.pixelSize: Style.font.body * 2
                opacity: 0.4
              }
            }

            PlainLabel {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.margins: Style.spacing.md
              anchors.top: previewBox.bottom
              anchors.topMargin: Style.spacing.md
              horizontalAlignment: Text.AlignHCenter
              text: cell.modelData.name
              font.bold: cell.active
            }

            PlainLabel {
              visible: cell.active
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.spacing.sm
              text: "✓ " + strings.t("panel.current")
              font.pixelSize: Style.font.body * 0.85
              opacity: 0.7
            }

            MouseArea {
              id: cellMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: window.picker.select(cell.modelData.id)
            }
          }
        }
      }
    }

    Row {
      id: sizeRow
      x: window.pad
      y: card.height - height - window.pad
      width: card.width - window.pad * 2
      height: Math.round(36 * Style.fontScale)
      spacing: Style.spacing.lg

      PlainLabel {
        id: sizeLabel
        anchors.verticalCenter: parent.verticalCenter
        text: strings.t("panel.size")
        opacity: 0.7
      }

      SizeButton {
        glyph: "−"
        enabled: window.picker && window.picker.size > CursorModel.MIN_SIZE
        onClicked: window.picker.setSize(window.picker.size - CursorModel.SIZE_STEP)
      }

      PlainLabel {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(48 * Style.fontScale)
        horizontalAlignment: Text.AlignHCenter
        text: window.picker ? window.picker.size + " px" : ""
        font.bold: true
      }

      SizeButton {
        glyph: "+"
        enabled: window.picker && window.picker.size < CursorModel.MAX_SIZE
        onClicked: window.picker.setSize(window.picker.size + CursorModel.SIZE_STEP)
      }
    }
  }

  component PlainLabel: Text {
    textFormat: Text.PlainText
    color: Commons.Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  component SizeButton: Rectangle {
    id: button

    property string glyph: ""
    signal clicked()

    width: height
    height: parent.height
    radius: Style.cornerRadius
    color: buttonMouse.containsMouse && button.enabled ? Style.hoverFill : Style.normalFill
    opacity: button.enabled ? 1 : 0.3

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: button.glyph
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body * 1.2
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: button.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }
  }
}
