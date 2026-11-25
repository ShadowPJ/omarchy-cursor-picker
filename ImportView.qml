import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
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
  readonly property var candidates: picker ? picker.candidates : []
  // What the list shows: archives from Downloads, or the archives a pasted
  // gnome-look page offers (the user picks one).
  readonly property var rows: {
    var out = []
    var i
    if (view.candidates.length > 0) {
      for (i = 0; i < view.candidates.length; i++)
        out.push({ kind: "candidate", title: view.candidates[i].name, subtitle: strings.t("import.candidate"),
                   size: CursorModel.formatBytes(view.candidates[i].sizeKb * 1024), data: view.candidates[i] })
    } else {
      for (i = 0; i < view.archives.length; i++)
        out.push({ kind: "archive", title: view.archives[i].name, subtitle: view.archives[i].themes.join(", "),
                   size: CursorModel.formatBytes(view.archives[i].size), data: view.archives[i] })
    }
    return out
  }
  readonly property var result: picker ? picker.importResult : null
  readonly property bool busy: picker ? picker.importBusy : false
  readonly property int rowHeight: Math.round(52 * Style.fontScale)

  onVisibleChanged: {
    if (!visible || !picker) return
    picker.clearImportResult()
    picker.scanArchives()
    urlField.text = ""
    urlField.forceActiveFocus()
  }

  function installSelected() {
    if (list.currentIndex < 0 || list.currentIndex >= view.rows.length) return
    var row = view.rows[list.currentIndex]
    if (row.kind === "candidate") picker.downloadCandidate(row.data, "skip")
    else picker.importArchive(row.data.path, "skip")
  }

  // One line saying how the last install went; empty before any attempt.
  readonly property string status: {
    var r = view.result
    if (view.busy) return strings.t("import.busy")
    if (view.candidates.length > 0) return strings.t("import.pick")
    if (!r || r.archive === "") return ""
    if (r.error) return strings.t("import.error." + r.error)
    if (r.installed.length === 0 && r.skipped.length === 0) return ""
    var parts = []
    if (r.installed.length > 0)
      parts.push(strings.tn("import.installed", r.installed.length).arg(Commons.I18n.formatNumber(r.installed.length)))
    if (r.skipped.length > 0)
      parts.push(strings.tn("import.skipped", r.skipped.length).arg(Commons.I18n.formatNumber(r.skipped.length)))
    return parts.join(" · ")
  }

  Keys.onEscapePressed: view.closed()
  Keys.onUpPressed: list.currentIndex = Math.max(0, list.currentIndex - 1)
  Keys.onDownPressed: list.currentIndex = Math.min(view.rows.length - 1, list.currentIndex + 1)
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
    id: urlRow
    anchors.top: header.bottom
    anchors.topMargin: Style.spacing.md
    width: parent.width
    height: Math.round(36 * Style.fontScale)
    spacing: Style.spacing.lg

    TextField {
      id: urlField
      width: parent.width - downloadButton.width - parent.spacing
      height: parent.height
      placeholderText: strings.t("import.url.placeholder")
      Keys.onEscapePressed: view.closed()
      onAccepted: if (text.trim() === "") view.installSelected(); else downloadButton.clicked()
    }

    TextButton {
      id: downloadButton
      height: parent.height
      enabled: !view.busy && urlField.text.trim() !== ""
      label: strings.t("import.download")
      onClicked: if (enabled) view.picker.importUrl(urlField.text, "skip", false)
    }
  }

  Row {
    id: statusRow
    anchors.top: urlRow.bottom
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
      onClicked: view.picker.replaceLast()
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
      visible: view.rows.length === 0 && picker && picker.archivesScanned
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
      model: view.rows
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

          PlainLabel { width: parent.width; text: row.modelData.title }
          PlainLabel {
            width: parent.width
            text: row.modelData.subtitle
            opacity: 0.6
            font.pixelSize: Style.font.body * 0.85
          }
        }

        PlainLabel {
          id: sizeLabel
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.size
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
