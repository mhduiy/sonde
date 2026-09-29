import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 总线浏览：名字列表 → 内省 → 接口/方法/信号/属性
Item {
    id: root

    property string bus: "session"
    property color fg: "#d7dde4"
    property color dim: "#7b8794"
    property color accent: "#4aa8ff"
    property color line: "#242c35"

    property var names: []
    property var tree: null

    /// 在浏览器里点中一个方法时抛出，交给调用面板预填
    signal methodChosen(string dest, string path, string iface, string member, string inSig)

    function refreshNames() {
        names = bridge.listNames(bus)
    }

    function go(dest, path) {
        destField.text = dest
        pathField.text = path
        tree = bridge.introspectTree(bus, dest, path)
    }

    onBusChanged: refreshNames()
    Component.onCompleted: {
        // 先看总线自己的内省，立刻就能用
        go("org.freedesktop.DBus", "/org/freedesktop/DBus")
        refreshNames()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            TextField {
                id: destField
                Layout.fillWidth: true
                placeholderText: "目标名，如 org.freedesktop.DBus"
                color: root.fg
                font.family: "monospace"
            }
            TextField {
                id: pathField
                Layout.preferredWidth: 230
                placeholderText: "/org/freedesktop/DBus"
                color: root.fg
                font.family: "monospace"
            }
            Button {
                text: "内省"
                onClicked: root.go(destField.text, pathField.text)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            ColumnLayout {
                Layout.preferredWidth: 250
                Layout.fillHeight: true
                spacing: 6

                TextField {
                    id: nameFilter
                    Layout.fillWidth: true
                    placeholderText: "筛选名字"
                    color: root.fg
                }
                ListView {
                    id: nameList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: {
                        var out = []
                        var f = nameFilter.text.toLowerCase()
                        for (var i = 0; i < root.names.length; ++i) {
                            if (f === "" || root.names[i].toLowerCase().indexOf(f) >= 0)
                                out.push(root.names[i])
                        }
                        return out
                    }
                    delegate: ItemDelegate {
                        required property var modelData
                        width: nameList.width
                        height: 30
                        text: modelData
                        font.family: "monospace"
                        font.pixelSize: 12
                        onClicked: root.go(modelData, "/")
                    }
                    ScrollBar.vertical: ScrollBar {}
                }
                Button {
                    Layout.fillWidth: true
                    text: "刷新名字"
                    onClicked: root.refreshNames()
                }
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: root.line
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: 10

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        visible: root.tree !== null && !root.tree.ok
                        text: root.tree && root.tree.error
                              ? ("内省失败：" + root.tree.error)
                              : "这个对象没有可用的内省信息。"
                        color: "#e06c75"
                    }

                    Repeater {
                        model: root.tree && root.tree.items ? root.tree.items : []
                        delegate: ColumnLayout {
                            id: entry
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 3

                            Button {
                                visible: entry.modelData.kind === "node"
                                flat: true
                                text: "▸ " + entry.modelData.name
                                font.family: "monospace"
                                onClicked: {
                                    var p = pathField.text
                                    if (p.endsWith("/")) p += entry.modelData.name
                                    else p += "/" + entry.modelData.name
                                    root.go(destField.text, p)
                                }
                            }

                            ColumnLayout {
                                visible: entry.modelData.kind === "interface"
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    text: entry.modelData.name
                                    color: root.accent
                                    font.bold: true
                                    font.family: "monospace"
                                }

                                Repeater {
                                    model: entry.modelData.methods
                                    delegate: ItemDelegate {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 26
                                        text: "  method   " + modelData.name
                                              + "(" + modelData.inSig + ") → " + modelData.outSig
                                        font.family: "monospace"
                                        font.pixelSize: 12
                                        onClicked: root.methodChosen(
                                            destField.text, pathField.text,
                                            entry.modelData.name, modelData.name,
                                            modelData.inSig)
                                    }
                                }
                                Repeater {
                                    model: entry.modelData.signals
                                    delegate: Label {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        text: "  signal   " + modelData.name + "(" + modelData.inSig + ")"
                                        color: "#9ece6a"
                                        font.family: "monospace"
                                        font.pixelSize: 12
                                    }
                                }
                                Repeater {
                                    model: entry.modelData.properties
                                    delegate: Label {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        text: "  property " + modelData.type + " " + modelData.name
                                              + "  [" + modelData.access + "]"
                                        color: "#e0af68"
                                        font.family: "monospace"
                                        font.pixelSize: 12
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
