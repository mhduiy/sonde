import QtQuick
import QtQuick.Controls
import org.deepin.dtk 1.0 as D
import QtQuick.Layouts

/// 左栏：总线上的服务。搜索框就在服务列表正上方——它搜的就是服务。
Rectangle {
    id: root

    property string bus: "session"
    signal serviceActivated(string dest)

    color: theme.surface

    property var names: []
    property string query: ""

    /// 唯一名（:1.x）排到已知服务后面，再按名字排序
    property var filtered: {
        var q = root.query.toLowerCase()
        var wellKnown = []
        var unique = []
        for (var i = 0; i < root.names.length; ++i) {
            var n = root.names[i]
            if (q !== "" && n.toLowerCase().indexOf(q) < 0)
                continue
            if (n.charAt(0) === ":")
                unique.push(n)
            else
                wellKnown.push(n)
        }
        wellKnown.sort()
        unique.sort()
        return wellKnown.concat(unique)
    }

    property int wellKnownCount: {
        var c = 0
        for (var i = 0; i < root.names.length; ++i)
            if (root.names[i].charAt(0) !== ":")
                ++c
        return c
    }

    function refresh() {
        names = bridge.listNames(root.bus)
    }

    onBusChanged: refresh()
    Component.onCompleted: refresh()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------------------------------------------------- 标题 + 搜索
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 66
            color: theme.surfaceAlt

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
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
                          + "（已知 " + root.wellKnownCount + "）"
                        color: theme.textFaint
                        font.pixelSize: 10
                    }
                    D.ToolButton {
                        text: "⟳"
                        implicitWidth: 24
                        implicitHeight: 22
                        onClicked: root.refresh()
                        ToolTip.visible: hovered
                        ToolTip.text: "重新列出总线上的服务"
                    }
                }

                D.TextField {
                    implicitHeight: 28
                    Layout.fillWidth: true
                    placeholderText: "搜索服务名"
                    onTextChanged: root.query = text
                    font.pixelSize: 12
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
                        color: row.isUnique ? theme.textDim : theme.text
                        font.family: "monospace"
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                    }
                    Rectangle {
                        implicitWidth: badge.implicitWidth + 8
                        implicitHeight: 15
                        radius: 2
                        color: row.isBus ? theme.accentSoft : theme.surfaceAlt
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

    // 服务切换时（比如点了消息里的 sender）滚到它那里去
    Connections {
        target: tree
        function onServiceChanged() {
            var idx = root.filtered.indexOf(tree.service)
            if (idx >= 0)
                Qt.callLater(function () { list.positionViewAtIndex(idx, ListView.Contain) })
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
