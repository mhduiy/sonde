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
    property string query: ""
    property var selectedNode: null
    property string activeBus: busBox.currentText

    function selectNode(row) {
        root.selectedNode = row
    }

    Component.onCompleted: {
        if (typeof initialBus !== "undefined" && initialBus !== "")
            busBox.currentIndex = (initialBus === "system" ? 1 : 0)
        if (typeof initialService !== "undefined" && initialService !== "")
            tree.setService(root.activeBus, initialService)
        if (typeof demoMode !== "undefined" && demoMode) {
            watchPane.expanded = true
            bridge.startMonitor(root.activeBus)
            // 自检/截图用：加一条服务级监听从流里有内容
            bridge.addWatch("service", root.activeBus, "org.freedesktop.DBus", "", "", "")
            // 展开第一个接口，再挑一个"带一个字符串参数"的方法
            // （GetNameOwner 这类），填个值真发一次，验证整条调用链路。
            var rows = tree.rows
            for (var i = 0; i < rows.length; ++i) {
                if (rows[i].kind === "interface") {
                    tree.toggle(rows[i].id)
                    break
                }
            }
            rows = tree.rows
            var picked = null
            for (var j = 0; j < rows.length; ++j) {
                if (rows[j].kind === "method" && rows[j].inSig === "s") {
                    picked = rows[j]
                    break
                }
            }
            if (picked === null) {
                for (var k = 0; k < rows.length; ++k) {
                    if (rows[k].kind === "method") {
                        picked = rows[k]
                        break
                    }
                }
            }
            if (picked !== null) {
                root.selectedNode = picked
                treePane.selectedId = picked.id
                Qt.callLater(function () { detailPane.demoRun("org.freedesktop.DBus") })
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

            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.topMargin: 8; Layout.bottomMargin: 8; color: theme.border }

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

            Button {
                text: bridge.monitoring ? "停止监听" : "开始监听"
                onClicked: bridge.monitoring
                           ? bridge.stopMonitor()
                           : bridge.startMonitor(root.activeBus)
            }

            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.topMargin: 8; Layout.bottomMargin: 8; color: theme.border }

            TextField {
                Layout.fillWidth: true
                placeholderText: "搜索服务名 / 接口 / 方法 / 信号（同时过滤左侧服务列表和对象树）"
                onTextChanged: {
                    root.query = text
                }
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
                SplitView.preferredWidth: 268
                SplitView.minimumWidth: 190
                query: root.query
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
                SplitView.preferredWidth: 440
                SplitView.minimumWidth: 320
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
