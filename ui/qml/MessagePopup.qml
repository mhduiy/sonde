import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "kinds.js" as K

/// 点消息流里的一条，弹出它的完整解码内容
Popup {
    id: root

    property var msg: null
    property var rows: []
    property var fields: {
        if (!root.msg)
            return []
        var out = []
        var keys = ["sender", "destination", "path", "interface", "member",
                    "error", "signature"]
        for (var i = 0; i < keys.length; ++i) {
            var v = root.msg[keys[i]]
            if (v !== undefined && v !== null && ("" + v) !== "")
                out.push({ k: keys[i], v: "" + v })
        }
        return out
    }

    onMsgChanged: rows = (msg && msg.args) ? bridge.flattenNodes(msg.args) : []

    modal: true
    focus: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(820, (Overlay.overlay ? Overlay.overlay.width : 900) - 80)
    height: Math.min(580, (Overlay.overlay ? Overlay.overlay.height : 700) - 80)
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

        // 标题
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            color: theme.surfaceAlt

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 8

                Rectangle {
                    visible: root.msg !== null
                    implicitWidth: 60
                    implicitHeight: 17
                    radius: 2
                    color: "transparent"
                    border.width: 1
                    border.color: root.msg ? K.msgColor(theme, root.msg.type) : theme.border
                    Label {
                        anchors.centerIn: parent
                        text: root.msg ? K.msgLabel(root.msg.type) : ""
                        color: root.msg ? K.msgColor(theme, root.msg.type) : theme.textDim
                        font.pixelSize: 9
                        font.bold: true
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: root.msg
                          ? ("#" + root.msg.serial + "   "
                             + (root.msg.member || root.msg.error || ""))
                          : ""
                    color: theme.text
                    font.bold: true
                    font.family: "monospace"
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }

                ToolButton {
                    text: "复制为文本"
                    implicitHeight: 24
                    onClicked: clip.put(bridge.messageToText(root.msg))
                }
                ToolButton {
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

        // 头部字段
        GridLayout {
            Layout.fillWidth: true
            Layout.margins: 12
            columns: 2
            columnSpacing: 14
            rowSpacing: 3

            Repeater {
                model: root.fields
                delegate: Label {
                    required property var modelData
                    required property int index
                    Layout.row: Math.floor(index / 2)
                    Layout.column: index % 2
                    text: modelData.k + ":  " + modelData.v
                    color: theme.textDim
                    font.family: "monospace"
                    font.pixelSize: 11
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.topMargin: 8
            visible: root.rows.length > 0
            text: "参数（按签名解码）"
            color: theme.textDim
            font.bold: true
            font.pixelSize: 11
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 12
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: 3

                Repeater {
                    model: root.rows
                    delegate: ValueRow {
                        required property var modelData
                        row: modelData
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: root.rows.length === 0
                    text: "这条消息没有参数。"
                    color: theme.textFaint
                    font.pixelSize: 11
                }
            }
        }

        // 底部：一键加监听
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 42
            color: theme.surfaceAlt

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    text: root.msg
                          ? (root.msg.interface ? (root.msg.interface + (root.msg.member ? "." + root.msg.member : "")) : "")
                          : ""
                    color: theme.textFaint
                    font.family: "monospace"
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                }
                Button {
                    text: "监听这条消息的来源"
                    enabled: root.msg !== null && (root.msg.member || "") !== ""
                    onClicked: {
                        var kind = root.msg.type === "signal" ? "member" : "member"
                        bridge.addWatch(kind, "", root.msg.sender || "",
                                        root.msg.path || "", root.msg.interface || "",
                                        root.msg.member || "")
                        root.close()
                    }
                }
            }
        }
    }

    Clip { id: clip }
}
