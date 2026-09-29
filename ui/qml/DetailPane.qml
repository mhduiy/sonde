import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 选中消息的完整类型化参数。
// 值树在 C++ 侧被拍平成带 depth 的行，这里用非递归列表渲染
// （QML 不允许组件自我实例化，扁平行同时也更适合大结构）。
Item {
    id: root

    property var msg: null
    property color fg: "#d7dde4"
    property color dim: "#7b8794"
    property color accent: "#4aa8ff"
    property color line: "#242c35"

    readonly property color strColor: "#9ece6a"
    readonly property color numColor: "#e0af68"
    readonly property color boolColor: "#bb9af7"
    readonly property color fdColor: "#7dcfff"

    readonly property var fields: {
        if (!root.msg) return []
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

    readonly property var rows:
        (root.msg && root.msg.args) ? bridge.flattenNodes(root.msg.args) : []

    function valueColor(kind, composite) {
        if (composite) return root.accent
        if (kind === "str" || kind === "path" || kind === "sig") return root.strColor
        if (kind === "bool") return root.boolColor
        if (kind === "fd") return root.fdColor
        return root.numColor
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: 12
        clip: true

        ColumnLayout {
            width: root.width - 24
            spacing: 10

            Label {
                visible: root.msg === null
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "在左侧点一条消息，这里会显示它的完整类型化参数。\n\n" +
                      "过滤框支持字段前缀：type:signal  iface:org.foo  member:Changed  " +
                      "path:/org/foo  sender::1.42   —— 空格分隔即 AND。"
                color: root.dim
            }

            ColumnLayout {
                visible: root.msg !== null
                Layout.fillWidth: true
                spacing: 6

                Label {
                    text: root.msg ? ("#" + root.msg.serial + "   " + root.msg.type) : ""
                    color: root.accent
                    font.bold: true
                    font.family: "monospace"
                    font.pixelSize: 13
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 16
                    rowSpacing: 2

                    Repeater {
                        model: root.fields
                        delegate: Label {
                            required property var modelData
                            required property int index
                            Layout.row: Math.floor(index / 2)
                            Layout.column: index % 2
                            text: modelData.k + ": " + modelData.v
                            color: root.fg
                            font.family: "monospace"
                            font.pixelSize: 12
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    height: 1
                    color: root.line
                    visible: root.rows.length > 0
                }

                Label {
                    visible: root.rows.length > 0
                    text: "参数（按签名解码，共 " + root.rows.length + " 个节点）"
                    color: root.dim
                    font.bold: true
                }

                Repeater {
                    model: root.rows
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

                        Item {
                            Layout.preferredWidth: modelData.depth * 16
                            Layout.fillHeight: true
                        }
                        Label {
                            Layout.preferredWidth: 130
                            text: modelData.label
                            color: root.dim
                            font.family: "monospace"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Label {
                            Layout.fillWidth: true
                            text: modelData.display
                            color: root.valueColor(modelData.kind, modelData.composite)
                            font.family: "monospace"
                            font.pixelSize: 12
                            wrapMode: Text.WrapAnywhere
                        }
                        Label {
                            text: modelData.composite ? modelData.sig : ""
                            color: root.dim
                            font.family: "monospace"
                            font.pixelSize: 10
                            opacity: 0.7
                        }
                    }
                }
            }
        }
    }
}
