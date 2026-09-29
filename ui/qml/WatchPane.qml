import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "kinds.js" as K

/// 底部可折叠面板：监听列表 + 实时消息流。
/// 监听是**附属功能**——平时折叠着，右键"加入监听列表"时会自动展开。
Rectangle {
    id: root

    property string bus: "session"
    property bool expanded: false

    implicitHeight: expanded ? 320 : 36
    color: theme.surface

    Behavior on implicitHeight {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------------------------------------------------- 标题栏
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 36
            color: theme.surfaceAlt

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 12
                spacing: 8

                ToolButton {
                    text: root.expanded ? "▾" : "▸"
                    implicitWidth: 24
                    implicitHeight: 24
                    onClicked: root.expanded = !root.expanded
                }
                Label {
                    text: "监听"
                    color: theme.text
                    font.bold: true
                    font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.expanded = !root.expanded
                    }
                }
                Label {
                    text: "(" + bridge.watches.length + " 项)"
                    color: theme.textFaint
                    font.pixelSize: 11
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    Layout.topMargin: 9
                    Layout.bottomMargin: 9
                    color: theme.border
                }

                Switch {
                    text: "只看监听列表"
                    checked: bridge.onlyWatched
                    onToggled: bridge.onlyWatched = checked
                    font.pixelSize: 11
                }

                Button {
                    text: bridge.paused
                          ? ("继续" + (bridge.pending > 0 ? " (+" + bridge.pending + ")" : ""))
                          : "暂停"
                    enabled: bridge.monitoring
                    implicitHeight: 24
                    onClicked: bridge.paused = !bridge.paused
                }
                Button {
                    text: "清空消息"
                    implicitHeight: 24
                    onClicked: bridge.clear()
                }

                Item { Layout.fillWidth: true }

                Label {
                    visible: root.expanded
                    text: "匹配 " + bridge.matched + "   收到 " + bridge.total
                          + "   显示 " + msgFilter.count
                    color: theme.textFaint
                    font.family: "monospace"
                    font.pixelSize: 11
                }
                Label {
                    visible: !bridge.monitoring
                    text: "未监听"
                    color: theme.warn
                    font.pixelSize: 11
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: theme.border
            }
        }

        // ---------------------------------------------------------- 内容
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.expanded
            spacing: 0

            // ---- 监听列表 ----
            Rectangle {
                Layout.preferredWidth: 320
                Layout.fillHeight: true
                color: theme.surface

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 26
                        color: theme.bg
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            Label {
                                text: "监听列表"
                                color: theme.textDim
                                font.pixelSize: 11
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            ToolButton {
                                text: "全部清除"
                                implicitHeight: 20
                                enabled: bridge.watches.length > 0
                                onClicked: bridge.clearWatches()
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: bridge.watches.length === 0
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.WordWrap
                        text: "还没有监听项\n\n在中间的树里右键任意\n路径 / 接口 / 方法 / 信号 / 属性\n选择「加入监听列表」"
                        color: theme.textFaint
                        font.pixelSize: 11
                    }

                    ListView {
                        id: watchList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: bridge.watches.length > 0
                        clip: true
                        model: bridge.watches
                        ScrollBar.vertical: ScrollBar {}

                        delegate: ItemDelegate {
                            id: wrow
                            required property var modelData
                            required property int index

                            width: watchList.width
                            height: 36

                            background: Rectangle {
                                color: wrow.hovered ? theme.hover : "transparent"
                            }

                            contentItem: RowLayout {
                                spacing: 6

                                Rectangle {
                                    implicitWidth: 44
                                    implicitHeight: 15
                                    radius: 2
                                    color: "transparent"
                                    border.width: 1
                                    border.color: K.colorFor(theme, wrow.modelData.kind)
                                    Label {
                                        anchors.centerIn: parent
                                        text: K.shortLabel(wrow.modelData.kind)
                                        color: K.colorFor(theme, wrow.modelData.kind)
                                        font.pixelSize: 8
                                        font.bold: true
                                    }
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: wrow.modelData.label
                                    color: theme.text
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }

                                ToolButton {
                                    text: "✕"
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    onClicked: bridge.removeWatch(wrow.index)
                                    ToolTip.visible: hovered
                                    ToolTip.text: "从监听列表移除"
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    width: 1
                    height: parent.height
                    color: theme.border
                }
            }

            // ---- 实时消息流 ----
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: theme.bg

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    ListView {
                        id: stream
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: msgFilter
                        reuseItems: true
                        cacheBuffer: 2000
                        ScrollBar.vertical: ScrollBar {}

                        property bool following: true
                        onMovementEnded: following = atYEnd

                        delegate: ItemDelegate {
                            id: srow
                            required property int index
                            required property string msgType
                            required property string member
                            required property string iface
                            required property string path
                            required property var raw
                            required property var timestampUs

                            width: stream.width
                            height: 26

                            background: Rectangle {
                                color: srow.hovered ? theme.hover : "transparent"
                            }

                            onClicked: {
                                popup.msg = srow.raw
                                popup.open()
                            }

                            contentItem: RowLayout {
                                spacing: 8

                                Label {
                                    Layout.preferredWidth: 74
                                    text: K.clockOf(srow.timestampUs)
                                    color: theme.textFaint
                                    font.family: "monospace"
                                    font.pixelSize: 10
                                }

                                Rectangle {
                                    implicitWidth: 52
                                    implicitHeight: 15
                                    radius: 2
                                    color: "transparent"
                                    border.width: 1
                                    border.color: K.msgColor(theme, srow.msgType)
                                    Label {
                                        anchors.centerIn: parent
                                        text: K.msgLabel(srow.msgType)
                                        color: K.msgColor(theme, srow.msgType)
                                        font.pixelSize: 8
                                        font.bold: true
                                    }
                                }

                                Label {
                                    Layout.preferredWidth: 190
                                    text: srow.iface
                                    color: theme.textDim
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    elide: Text.ElideMiddle
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: srow.member !== "" ? srow.member : "—"
                                    color: theme.text
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                                Label {
                                    Layout.preferredWidth: 150
                                    text: srow.path
                                    color: theme.textFaint
                                    font.family: "monospace"
                                    font.pixelSize: 10
                                    elide: Text.ElideMiddle
                                }
                            }
                        }

                        onCountChanged: if (following) Qt.callLater(positionViewAtEnd)
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        visible: stream.count === 0
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: bridge.monitoring
                              ? (bridge.onlyWatched && bridge.watches.length > 0
                                 ? "还没有匹配到监听列表里的消息…"
                                 : "还没有收到消息…")
                              : "点顶部的「开始监听」开始接收消息"
                        color: theme.textFaint
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    MessagePopup { id: popup }
}
