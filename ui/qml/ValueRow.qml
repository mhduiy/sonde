import QtQuick
import QtQuick.Controls
import org.deepin.dtk 1.0 as D
import QtQuick.Layouts
import "kinds.js" as K

/// 一行值（来自 bridge.flattenNodes）。
/// 会自动识别"字符串里装的是 JSON"（deepin 的接口很爱这么干），
/// 提供一键格式化查看和复制。
ColumnLayout {
    id: root

    required property var row
    property bool expandJson: typeof jsonExpanded !== "undefined" ? jsonExpanded : false

    readonly property int lineCount:
        (root.row.json === true && root.row.jsonPretty)
        ? ("" + root.row.jsonPretty).split("\n").length : 0

    Layout.fillWidth: true
    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Item {
            Layout.preferredWidth: root.row.depth * 14
            Layout.fillHeight: true
        }

        Label {
            Layout.preferredWidth: 104
            text: root.row.label !== undefined ? ("" + root.row.label) : ""
            color: theme.textFaint
            font.family: "monospace"
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Label {
            Layout.fillWidth: true
            visible: !(root.row.json === true && root.expandJson)
            text: root.row.display !== undefined ? ("" + root.row.display) : ""
            color: K.valueColor(theme, root.row.kind, root.row.composite)
            font.family: "monospace"
            font.pixelSize: 12
            elide: root.row.json === true ? Text.ElideRight : Text.ElideNone
            wrapMode: root.row.json === true ? Text.NoWrap : Text.WrapAnywhere
        }

        Label {
            text: root.row.sig !== undefined ? ("" + root.row.sig) : ""
            color: theme.textFaint
            font.family: "monospace"
            font.pixelSize: 10
            visible: root.row.composite === true
        }

        Rectangle {
            visible: root.row.json === true
            implicitWidth: jsonChip.implicitWidth + 10
            implicitHeight: 16
            radius: 2
            color: theme.accentSoft
            Label {
                id: jsonChip
                anchors.centerIn: parent
                text: "JSON"
                color: theme.accent
                font.pixelSize: 9
                font.bold: true
            }
        }

        D.ToolButton {
            visible: root.row.json === true
            text: root.expandJson ? "收起" : "格式化"
            implicitHeight: 22
            onClicked: root.expandJson = !root.expandJson
        }

        D.ToolButton {
            text: "复制"
            implicitHeight: 22
            onClicked: clip.put(root.row.json === true && root.row.jsonPretty !== ""
                                ? root.row.jsonPretty
                                : ("" + root.row.display))
            ToolTip.visible: hovered
            ToolTip.text: root.row.json === true ? "复制格式化后的 JSON" : "复制这个值"
        }
    }

    // 展开的 JSON 块：行号 + 高亮 + 可滚动可选中，还能放大到全屏看
    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 14 + root.row.depth * 14
        visible: root.row.json === true && root.expandJson
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Label {
                text: "已识别为 JSON（" + root.lineCount + " 行）"
                color: theme.textFaint
                font.pixelSize: 10
            }
            Item { Layout.fillWidth: true }
            D.ToolButton {
                text: "放大查看"
                implicitHeight: 20
                onClicked: if (viewerLoader.item) viewerLoader.item.open()
            }
            D.ToolButton {
                text: "复制全部"
                implicitHeight: 20
                onClicked: clip.put(root.row.jsonPretty)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 260
            color: theme.bg
            border.color: theme.border
            radius: 3
            clip: true

            CodeView {
                anchors.fill: parent
                anchors.margins: 2
                text: root.row.jsonPretty
            }
        }
    }

    // 只有真的是 JSON 的行才创建放大视图
    Loader {
        id: viewerLoader
        active: root.row.json === true
        sourceComponent: jsonViewerComponent
    }

    Component {
        id: jsonViewerComponent
        JsonViewerPopup {
            text: root.row.jsonPretty
            title: "JSON — " + root.lineCount + " 行"
        }
    }

    Clip { id: clip }
}
