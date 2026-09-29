import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root

    visible: true
    width: 1480
    height: 920
    minimumWidth: 1000
    minimumHeight: 640
    title: "Sonde — D-Bus 观察台"
    color: theme.bg

    // 共享状态
    property var selectedNode: null
    property string activeBus: busBox.currentText

    Component.onCompleted: {
        if (typeof initialBus !== "undefined" && initialBus !== "")
            busBox.currentIndex = (initialBus === "system" ? 1 : 0)
        if (typeof initialService !== "undefined" && initialService !== "")
            tree.setService(root.activeBus, initialService)
        if (typeof demoMode !== "undefined" && demoMode) {
            watchPane.expanded = true
            bridge.startMonitor(root.activeBus)
            bridge.addWatch("service", root.activeBus, "org.freedesktop.DBus", "", "", "")
            // 自检：找到一个"带一个字符串参数"的方法，填值真发一次
            function pickNode() {
                var rows = tree.rows
                var want = (typeof demoMethod !== "undefined") ? demoMethod : ""
                var firstMethod = null
                for (var j = 0; j < rows.length; ++j) {
                    if (want !== "" && rows[j].name === want)
                        return rows[j]
                    if (rows[j].kind !== "method")
                        continue
                    if (firstMethod === null)
                        firstMethod = rows[j]
                    if (want === "" && rows[j].inSig === "s")
                        return rows[j]
                }
                return firstMethod
            }

            var picked = pickNode()
            if (picked === null) {
                // 接口还没展开：展开第一个（注意别 toggle 已经展开的，否则就收起来了）
                var rows0 = tree.rows
                for (var i = 0; i < rows0.length; ++i) {
                    if (rows0[i].kind === "interface" && !rows0[i].expanded) {
                        tree.toggle(rows0[i].id)
                        break
                    }
                }
                picked = pickNode()
            }
            if (picked !== null) {
                root.selectedNode = picked
                treePane.selectedId = picked.id
                var seed = (typeof demoSeed !== "undefined" && demoSeed !== "")
                           ? demoSeed : "org.freedesktop.DBus"
                if (picked.kind === "property") {
                    Qt.callLater(function () { detailPane.readProperty(picked) })
                } else if (picked.kind === "method") {
                    Qt.callLater(function () { detailPane.demoRun(seed) })
                }
            }
        }
    }

    // ---------------------------------------------------------------- 顶部工具栏
    header: ToolBar {
        background: Rectangle {
            color: theme.surface
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: theme.border
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Label {
                text: "Sonde"
                color: theme.accent
                font.bold: true
                font.pixelSize: 17
            }
            Label {
                text: "D-Bus 观察台"
                color: theme.textFaint
                font.pixelSize: 12
                Layout.rightMargin: 6
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                Layout.topMargin: 8
                Layout.bottomMargin: 8
                color: theme.border
            }

            Label { text: "总线"; color: theme.textDim; font.pixelSize: 12 }
            ComboBox {
                id: busBox
                model: ["session", "system"]
                Layout.preferredWidth: 116
                onActivated: {
                    if (tree.service !== "")
                        tree.setService(currentText, tree.service)
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                visible: bridge.monitoring
                text: bridge.monitoring
                      ? ("监听中 · 收到 " + bridge.total + " 条" + (bridge.paused ? "（已暂停）" : ""))
                      : ""
                color: bridge.monitoring ? theme.ok : theme.textFaint
                font.pixelSize: 11
            }

            Button {
                text: theme.dark ? "☀  浅色" : "☾  深色"
                onClicked: theme.dark = !theme.dark
            }
        }
    }

    // ---------------------------------------------------------------- 提示条
    Rectangle {
        id: noticeBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: visible ? noticeLabel.implicitHeight + 14 : 0
        color: theme.dark ? "#3a2a1a" : "#fff4e0"
        border.color: theme.warn
        border.width: 1
        visible: false
        z: 20

        Label {
            id: noticeLabel
            anchors.fill: parent
            anchors.margins: 7
            wrapMode: Text.WordWrap
            color: theme.warn
            text: ""
        }

        MouseArea {
            anchors.fill: parent
            onClicked: noticeBar.visible = false
        }

        Timer {
            id: noticeTimer
            interval: 20000
            onTriggered: noticeBar.visible = false
        }
    }

    Connections {
        target: bridge
        function onNotice(level, text) {
            noticeLabel.text = "⚠  " + text + "    （点击关闭）"
            noticeLabel.color = level === "error" ? theme.error : theme.warn
            noticeBar.color = level === "error"
                             ? (theme.dark ? "#3a1f1f" : "#fdeaea")
                             : (theme.dark ? "#3a2a1a" : "#fff4e0")
            noticeBar.border.color = noticeLabel.color
            noticeBar.visible = true
            noticeTimer.restart()
        }
    }

    // ---------------------------------------------------------------- 主体
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        SplitView {
            id: browseSplit
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: Qt.Horizontal

            handle: Rectangle {
                implicitWidth: 1
                implicitHeight: 1
                color: theme.border
            }

            ServicePane {
                SplitView.preferredWidth: 288
                SplitView.minimumWidth: 200
                bus: root.activeBus
                onServiceActivated: (dest) => {
                    tree.setService(root.activeBus, dest)
                    root.selectedNode = null
                }
            }

            TreePane {
                id: treePane
                SplitView.fillWidth: true
                SplitView.minimumWidth: 380
                onNodeSelected: (row) => { root.selectedNode = row }
                onReadPropertyRequested: (n) => detailPane.readProperty(n)
            }

            DetailPane {
                id: detailPane
                SplitView.preferredWidth: 460
                SplitView.minimumWidth: 340
                node: root.selectedNode
                bus: root.activeBus
            }
        }

        WatchPane {
            id: watchPane
            Layout.fillWidth: true
            bus: root.activeBus
        }
    }
}
