import QtQuick
import QtQuick.Controls
import org.deepin.dtk 1.0 as D
import QtQuick.Layouts

/// 全屏查看 JSON：行号 + 高亮 + 双向滚动 + 一键复制全部。
/// 112 行这种长度塞在右栏里根本没法看，所以给一个放大视图。
Popup {
    id: root

    property string text: ""
    property string title: "JSON"

    modal: true
    focus: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(1040, (Overlay.overlay ? Overlay.overlay.width : 1200) - 80)
    height: Math.min(740, (Overlay.overlay ? Overlay.overlay.height : 820) - 80)
    padding: 0

    background: Rectangle {
        color: theme.surface
        border.color: theme.borderStrong
        border.width: 1
        radius: 6
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            color: theme.surfaceAlt

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 8

                Label {
                    text: root.title
                    color: theme.text
                    font.bold: true
                    font.family: "monospace"
                    font.pixelSize: 12
                }
                Item { Layout.fillWidth: true }

                D.CheckBox {
                    text: "自动换行"
                    checked: codeView.wrap
                    onToggled: codeView.wrap = checked
                    font.pixelSize: 11
                }
                D.Button {
                    text: "复制全部"
                    implicitHeight: 24
                    onClicked: clip.put(root.text)
                }
                D.ToolButton {
                    text: "✕"
                    implicitWidth: 26
                    implicitHeight: 24
                    onClicked: root.close()
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: theme.border
            }
        }

        CodeView {
            id: codeView
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: root.text
        }
    }

    Clip { id: clip }
}
