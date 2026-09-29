import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root

    visible: true
    width: 1420
    height: 880
    title: "Sonde — D-Bus 观察台"
    color: "#0f1216"

    readonly property color bg: "#0f1216"
    readonly property color panel: "#161b21"
    readonly property color panelAlt: "#1b2229"
    readonly property color line: "#242c35"
    readonly property color fg: "#d7dde4"
    readonly property color dim: "#7b8794"
    readonly property color accent: "#4aa8ff"

    property var selected: null

    Component.onCompleted: {
        if (typeof initialTab !== "undefined")
            tabs.currentIndex = initialTab
        if (typeof initialBus !== "undefined" && initialBus !== "")
            busBox.currentIndex = (initialBus === "system" ? 1 : 0)
    }

    // 自检/截图用：自动挑一条"参数最丰富"的消息显示出来
    function pickInterestingMessage() {
        if (root.selected !== null)
            return
        for (var i = msgFilter.count - 1; i >= 0; --i) {
            var m = msgFilter.at(i)
            if (m && m.args && m.args.length > 0) {
                root.selected = m
                return
            }
        }
        if (msgFilter.count > 0)
            root.selected = msgFilter.at(msgFilter.count - 1)
    }

    Connections {
        target: msgFilter
        function onRowsInserted() {
            if (typeof autoSelectFirst !== "undefined" && autoSelectFirst)
                root.pickInterestingMessage()
        }
    }

    function typeColor(t) {
        if (t === "signal") return "#9ece6a"
        if (t === "method_call") return "#4aa8ff"
        if (t === "method_return") return "#e0af68"
        if (t === "error") return "#e06c75"
        return dim
    }

    function typeBadge(t) {
        if (t === "method_call") return "CALL"
        if (t === "method_return") return "RET"
        if (t === "signal") return "SIGNAL"
        if (t === "error") return "ERROR"
        return t
    }

    header: ToolBar {
        background: Rectangle { color: root.panel }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            Label {
                text: "◉ Sonde"
                color: root.fg
                font.bold: true
                font.pixelSize: 16
            }

            ComboBox {
                id: busBox
                model: ["session", "system"]
                Layout.preferredWidth: 118
            }

            Button {
                text: bridge.monitoring ? "停止监听" : "开始监听"
                onClicked: bridge.monitoring
                           ? bridge.stopMonitor()
                           : bridge.startMonitor(busBox.currentText)
            }

            Button {
                enabled: bridge.monitoring
                text: bridge.paused
                      ? ("继续" + (bridge.pending > 0 ? " (+" + bridge.pending + ")" : ""))
                      : "暂停"
                onClicked: bridge.paused = !bridge.paused
            }

            Button {
                text: "清空"
                onClicked: bridge.clear()
            }

            TextField {
                Layout.fillWidth: true
                placeholderText: "过滤：type:signal  iface:org.foo  member:Changed   （空格分隔，AND）"
                onTextChanged: msgFilter.query = text
            }

            Label {
                text: "显示 " + msgFilter.count + " / 收到 " + bridge.total
                color: root.dim
                font.family: "monospace"
                font.pixelSize: 12
            }
        }
    }

    Rectangle {
        id: noticeBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: visible ? noticeLabel.implicitHeight + 14 : 0
        color: "#3a2a1a"
        visible: false
        z: 20

        Label {
            id: noticeLabel
            anchors.fill: parent
            anchors.margins: 7
            wrapMode: Text.WordWrap
            color: "#ffd591"
            text: ""
        }

        Timer {
            id: noticeTimer
            interval: 15000
            onTriggered: noticeBar.visible = false
        }
    }

    Connections {
        target: bridge
        function onNotice(level, text) {
            noticeLabel.text = "⚠  " + text
            noticeBar.color = level === "error" ? "#3a1f1f" : "#3a2a1a"
            noticeLabel.color = level === "error" ? "#ffa8a8" : "#ffd591"
            noticeBar.visible = true
            noticeTimer.restart()
        }
    }

    SplitView {
        anchors.fill: parent
        orientation: Qt.Horizontal

        // ------------------------------------------------ 左：消息流
        Rectangle {
            SplitView.preferredWidth: 680
            SplitView.minimumWidth: 380
            color: root.bg

            ListView {
                id: messageList
                anchors.fill: parent
                clip: true
                model: msgFilter
                reuseItems: true
                cacheBuffer: 3000
                ScrollBar.vertical: ScrollBar {}

                // 只有本来就在底部时才自动跟随，避免用户往上翻时被拽走
                property bool following: true
                onMovementEnded: following = atYEnd

                delegate: ItemDelegate {
                    id: row
                    required property int index
                    required property string msgType
                    required property string member
                    required property string iface
                    required property string signature
                    required property var args
                    required property var raw

                    width: messageList.width
                    height: 38

                    highlighted: root.selected !== null
                                 && root.selected.timestamp_us === raw.timestamp_us
                                 && root.selected.serial === raw.serial

                    onClicked: root.selected = raw

                    background: Rectangle {
                        color: row.highlighted
                               ? "#20303f"
                               : (index % 2 === 0 ? root.panel : root.panelAlt)
                    }

                    contentItem: RowLayout {
                        spacing: 10

                        Item {
                            Layout.preferredWidth: 84
                            Layout.fillHeight: true

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 78
                                height: 18
                                radius: 3
                                color: root.typeColor(row.msgType)
                                opacity: 0.20
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.typeBadge(row.msgType)
                                color: root.typeColor(row.msgType)
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: row.member !== ""
                                  ? (row.member + "   " + (row.iface || ""))
                                  : (row.msgType === "method_return" ? "←  返回" : "—")
                            color: root.fg
                            elide: Text.ElideRight
                            font.family: "monospace"
                            font.pixelSize: 12
                        }

                        Label {
                            text: row.signature
                            color: root.dim
                            font.family: "monospace"
                            font.pixelSize: 11
                        }
                    }
                }

                onCountChanged: if (following) Qt.callLater(positionViewAtEnd)
            }
        }

        // ------------------------------------------------ 右：详情 / 浏览
        Rectangle {
            SplitView.fillWidth: true
            color: root.panel

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                TabBar {
                    id: tabs
                    Layout.fillWidth: true
                    TabButton { text: "消息详情" }
                    TabButton { text: "总线浏览" }
                    TabButton { text: "方法调用" }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: tabs.currentIndex

                    DetailPane {
                        msg: root.selected
                        fg: root.fg
                        dim: root.dim
                        accent: root.accent
                        line: root.line
                    }

                    BrowserPane {
                        id: browserPane
                        bus: busBox.currentText
                        fg: root.fg
                        dim: root.dim
                        accent: root.accent
                        line: root.line
                        onMethodChosen: (dest, path, iface, member, inSig) => {
                            callPane.loadFrom(dest, path, iface, member, inSig)
                            tabs.currentIndex = 2
                        }
                    }

                    CallPane {
                        id: callPane
                        bus: busBox.currentText
                        fg: root.fg
                        dim: root.dim
                        accent: root.accent
                        line: root.line
                    }
                }
            }
        }
    }
}
