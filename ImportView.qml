import QtQuick
import qs.Commons
import qs.Commons as Commons
import "CursorModel.js" as CursorModel

// The panel's import view: archives in Downloads that hold a cursor theme.
// Enter or a click installs; "Replace" overwrites themes that were skipped
// because they already exist; Esc goes back.
FocusScope {
  id: view

  property var picker: null
  signal closed()

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property var archives: picker ? picker.archives : []
  readonly property var result: picker ? picker.importResult : null
  readonly property bool busy: picker ? picker.importBusy : false
  readonly property int rowHeight: Math.round(52 * Style.fontScale)

  onVisibleChanged: {
    if (!visible || !picker) return
    picker.scanArchives()
    view.forceActiveFocus()
  }

  function installSelected() {
    if (list.currentIndex >= 0 && list.currentIndex < view.archives.length)
      picker.importArchive(view.archives[list.currentIndex].path, "skip")
  }

  // One line saying how the last install went; empty before any attempt.
  readonly property string status: {
    var r = view.result
    if (view.busy) return strings.t("import.busy")
    if (!r || r.archive === "") return ""
    if (r.error) return strings.t("import.error." + r.error)
    var parts = []
    if (r.installed.length > 0)
      parts.push(strings.tn("import.installed", r.installed.length).arg(Commons.I18n.formatNumber(r.installed.length)))
    if (r.skipped.length > 0)
      parts.push(strings.tn("import.skipped", r.skipped.length).arg(Commons.I18n.formatNumber(r.skipped.length)))
    return parts.join(" · ")
  }

  Keys.onEscapePressed: view.closed()
  Keys.onUpPressed: list.currentIndex = Math.max(0, list.currentIndex - 1)
  Keys.onDownPressed: list.currentIndex = Math.min(view.archives.length - 1, list.currentIndex + 1)
  Keys.onReturnPressed: view.installSelected()
  Keys.onEnterPressed: view.installSelected()

  Row {
    id: header
    width: parent.width
    height: Math.round(36 * Style.fontScale)
    spacing: Style.spacing.lg

    TextButton {
      label: "← " + strings.t("import.back")
      onClicked: view.closed()
    }

    PlainLabel {
      anchors.verticalCenter: parent.verticalCenter
      text: strings.t("import.title")
      font.bold: true
    }
  }

  Row {
    id: statusRow
    anchors.top: header.bottom
    anchors.topMargin: Style.spacing.md
    width: parent.width
    height: statusText.text !== "" ? Math.round(36 * Style.fontScale) : 0
    spacing: Style.spacing.lg
    visible: statusText.text !== ""

    PlainLabel {
      id: statusText
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, parent.width - (replaceButton.visible ? replaceButton.width + parent.spacing : 0))
      text: view.status
      color: view.result && view.result.error ? Commons.Color.urgent : Commons.Color.popups.text
    }

    TextButton {
      id: replaceButton
      visible: !!view.result && view.result.skipped.length > 0 && !view.busy
      label: strings.t("import.replace")
      onClicked: view.picker.importArchive(view.result.archive, "replace")
    }
  }

  Rectangle {
    anchors.top: statusRow.bottom
    anchors.topMargin: Style.spacing.md
    anchors.bottom: parent.bottom
    width: parent.width
    radius: Style.cornerRadius
    color: Style.normalFill

    PlainLabel {
      visible: view.archives.length === 0 && picker && picker.archivesScanned
      anchors.centerIn: parent
      width: parent.width - Style.spacing.xxl * 2
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: strings.t("import.empty")
      opacity: 0.6
    }

    ListView {
      id: list
      anchors.fill: parent
      anchors.margins: Style.spacing.sm
      clip: true
      model: view.archives
      currentIndex: 0
      boundsBehavior: Flickable.StopAtBounds

      delegate: Rectangle {
        id: row
        required property var modelData
        required property int index
        width: list.width
        height: view.rowHeight
        radius: Style.cornerRadius
        color: rowMouse.containsMouse || ListView.isCurrentItem ? Style.hoverFill : "transparent"

        Column {
          anchors.left: parent.left
          anchors.right: sizeLabel.left
          anchors.leftMargin: Style.spacing.lg
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter

          PlainLabel { width: parent.width; text: row.modelData.name }
          PlainLabel {
            width: parent.width
            text: row.modelData.themes.join(", ")
            opacity: 0.6
            font.pixelSize: Style.font.body * 0.85
          }
        }

        PlainLabel {
          id: sizeLabel
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          text: CursorModel.formatBytes(row.modelData.size)
          opacity: 0.6
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          enabled: !view.busy
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            list.currentIndex = row.index
            view.installSelected()
          }
        }
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
}
