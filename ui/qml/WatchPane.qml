import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.deepin.dtk 1.0 as D
import "kinds.js" as K

/// 底部面板：过滤框 + 实时消息流。
///
/// 设计：不再有"监听列表"，只有**一个过滤表达式**。
/// - 过滤框为空 → 全看；非空 → 只看命中的（空格分隔即 AND）
/// - 右键"加入过滤条件"就是往这个框里追加词条
/// - 好处：条件改了立刻重筛**已有的缓冲**，不是只对将来的消息生效
Rectangle {
    id: root

    property string bus: "session"
    property bool expanded: false

    /// 点消息里的 sender / 接收者 → 跳到那个服务
    signal serviceJumpRequested(string name)

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

                D.ToolButton {
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

                D.Button {
                    text: bridge.monitoring ? "停止监听" : "开始监听"
                    implicitHeight: 24
                    visible: root.width > 640
                    onClicked: bridge.monitoring
                               ? bridge.stopMonitor()
                               : bridge.startMonitor(root.bus)
                }

                // 过滤框：整个面板的核心控件
                TextField {
                    id: filterField
                    Layout.fillWidth: true
                    Layout.minimumWidth: 110
                    implicitHeight: 26
                    placeholderText: "过滤：iface:  member:  path:  svc:  prop:  type:signal"
                    font.family: "monospace"
                    font.pixelSize: 11
                    text: msgFilter.query
                    onTextChanged: msgFilter.query = text
                    ToolTip.visible: hovered
                    ToolTip.text: "空格分隔多个条件是 AND；不带字段名则在全部内容里找子串"
                }
                D.ToolButton {
                    text: "✕"
                    implicitWidth: 26
                    implicitHeight: 24
                    visible: msgFilter.query !== ""
                    onClicked: msgFilter.query = ""
                    ToolTip.visible: hovered
                    ToolTip.text: "清空过滤条件"
                }

                Label {
                    visible: root.expanded && root.width > 960
                    text: "显示 " + msgFilter.count + " / 收到 " + bridge.total
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

                D.ToolButton {
                    text: "⋯"
                    implicitWidth: 28
                    implicitHeight: 24
                    onClicked: watchMenu.popup()
                    ToolTip.visible: hovered
                    ToolTip.text: "更多"
                }
            }

            Menu {
                id: watchMenu
                MenuItem {
                    text: bridge.monitoring ? "停止监听" : "开始监听"
                    onTriggered: bridge.monitoring
                                 ? bridge.stopMonitor()
                                 : bridge.startMonitor(root.bus)
                }
                MenuSeparator {}
                MenuItem {
                    text: bridge.paused ? "继续接收" : "暂停接收"
                    enabled: bridge.monitoring
                    onTriggered: bridge.paused = !bridge.paused
                }
                MenuItem {
                    text: "清空消息"
                    onTriggered: bridge.clear()
                }
                MenuItem {
                    text: "清空过滤条件"
                    enabled: msgFilter.query !== ""
                    onTriggered: msgFilter.query = ""
                }
                MenuSeparator {}
                MenuItem {
                    text: "显示 " + msgFilter.count + " / 收到 " + bridge.total
                    enabled: false
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: theme.border
            }
        }

        // ---------------------------------------------------------- 消息流
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.expanded
            color: theme.bg

            ListView {
                id: stream
                anchors.fill: parent
                clip: true
                model: msgFilter
                reuseItems: true
                cacheBuffer: 3000
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                property bool following: true
                onMovementEnded: following = atYEnd

                delegate: ItemDelegate {
                    id: srow
                    required property int index
                    required property string msgType
                    required property string member
                    required property string path
                    required property string summary
                    required property var raw

                    width: stream.width
                    height: 26

                    background: Rectangle {
                        color: srow.hovered ? theme.hover : "transparent"
                    }

                    onClicked: {
                        popup.msg = srow.raw
                        popup.open()
                    }

                    // 普通 Row + 显式宽度：需要省略的列给 elide，
                    // 宽度确定才不会像 RowLayout 那样溢出被裁（见 README 第 10 条）
                    contentItem: Row {
                        id: srowContent
                        spacing: 6

                        readonly property real fixed:
                            66 + 52 + 130 + 112 + 12 + 170 + 160 + 6 * 7

                        Label {
                            width: 66
                            height: srow.height
                            verticalAlignment: Text.AlignVCenter
                            text: K.clockOf(srow.raw.timestamp_us)
                            color: theme.textFaint
                            font.family: "monospace"
                            font.pixelSize: 10
                        }

                        Rectangle {
                            width: 52
                            height: 15
                            y: (srow.height - height) / 2
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

                        // sender → 接收者：都能点，点了跳到那个服务
                        ClickableName {
                            width: 130
                            height: srow.height
                            name: (srow.raw.sender !== undefined && srow.raw.sender !== null)
                                  ? ("" + srow.raw.sender) : ""
                            onClicked: root.serviceJumpRequested(srow.raw.sender)
                        }
                        Label {
                            width: 12
                            height: srow.height
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: "→"
                            color: theme.textFaint
                            font.pixelSize: 10
                        }
                        ClickableName {
                            width: 100
                            height: srow.height
                            name: (srow.raw.destination !== undefined
                                   && srow.raw.destination !== null)
                                  ? ("" + srow.raw.destination) : ""
                            emptyText: "（广播）"
                            onClicked: root.serviceJumpRequested(srow.raw.destination)
                        }

                        Label {
                            width: 170
                            height: srow.height
                            verticalAlignment: Text.AlignVCenter
                            text: srow.raw.interface !== undefined
                                  ? ("" + srow.raw.interface) : ""
                            color: theme.textDim
                            font.family: "monospace"
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                        }

                        // 一行摘要：PropertiesChanged 会显示"属性 = 值"
                        Label {
                            width: Math.max(60, srow.width - srowContent.fixed)
                            height: srow.height
                            verticalAlignment: Text.AlignVCenter
                            text: (srow.member !== "" ? (srow.member + "   ") : "")
                                  + srow.summary
                            color: srow.summary !== "" ? theme.accent : theme.text
                            font.family: "monospace"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }

                        Label {
                            width: 160
                            height: srow.height
                            verticalAlignment: Text.AlignVCenter
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
                anchors.fill: parent
                anchors.margins: 12
                visible: stream.count === 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                text: !bridge.monitoring
                      ? "点「开始监听」开始接收消息"
                      : (msgFilter.query !== ""
                         ? "没有消息命中这个过滤条件：\n" + msgFilter.query
                         : "还没有收到消息…")
                color: theme.textFaint
                font.pixelSize: 11
            }
        }
    }

    MessagePopup { id: popup }
}
