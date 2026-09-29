import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/// 左栏：总线上的服务（名字）
Rectangle {
    id: root

    property string query: ""
    property string bus: "session"
    signal serviceActivated(string dest)

    color: theme.surface

    property var names: []
    property var filtered: {
        var q = root.query.toLowerCase()
        if (q === "")
            return root.names
        var out = []
        for (var i = 0; i < root.names.length; ++i) {
            if (root.names[i].toLowerCase().indexOf(q) >= 0)
                out.push(root.names[i])
        }
        return out
    }

    function refresh() {
        names = bridge.listNames(root.bus)
    }

    onBusChanged: refresh()
    Component.onCompleted: refresh()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 34
            color: theme.surfaceAlt

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                spacing: 6

                Label {
                    text: "服务"
                    color: theme.text
                    font.bold: true
                    font.pixelSize: 12
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: root.filtered.length + " / " + root.names.length
                    color: theme.textFaint
                    font.pixelSize: 11
                }
                ToolButton {
                    text: "⟳"
                    implicitWidth: 26
                    implicitHeight: 24
                    onClicked: root.refresh()
                    ToolTip.visible: hovered
                    ToolTip.text: "重新列出总线上的服务"
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: theme.border
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.filtered
            ScrollBar.vertical: ScrollBar {}
            reuseItems: true

            delegate: ItemDelegate {
                id: row
                required property var modelData
                width: list.width
                height: 30

                readonly property bool isUnique: modelData.startsWith(":")
                readonly property bool isBus: modelData === "org.freedesktop.DBus"
                readonly property bool current: tree.service === modelData

                highlighted: current
                background: Rectangle {
                    color: row.current ? theme.selected
                                       : (row.hovered ? theme.hover : "transparent")
                }

                onClicked: root.serviceActivated(row.modelData)

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: {
                        serviceMenu.target = row.modelData
                        serviceMenu.popup()
                    }
                }

                contentItem: RowLayout {
                    spacing: 6
                    Label {
                        Layout.fillWidth: true
                        text: row.modelData
                        color: theme.text
                        font.family: "monospace"
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                    }
                    Rectangle {
                        implicitWidth: badge.implicitWidth + 8
                        implicitHeight: 15
                        radius: 2
                        color: row.isBus ? theme.accentSoft
                                         : (row.isUnique ? theme.surfaceAlt : theme.surfaceAlt)
                        Label {
                            id: badge
                            anchors.centerIn: parent
                            text: row.isBus ? "总线" : (row.isUnique ? "唯一" : "已知")
                            color: row.isBus ? theme.accent : theme.textDim
                            font.pixelSize: 9
                        }
                    }
                }
            }
        }
    }

    Menu {
        id: serviceMenu
        property string target: ""

        MenuItem {
            text: "打开这个服务"
            onTriggered: root.serviceActivated(serviceMenu.target)
        }
        MenuItem {
            text: "加入监听列表（该服务的全部消息）"
            onTriggered: bridge.addWatch("service", root.bus, serviceMenu.target, "", "", "")
        }
        MenuSeparator {}
        MenuItem {
            text: "复制服务名"
            onTriggered: clip.put(serviceMenu.target)
        }
    }

    Clip { id: clip }
}
