import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.deepin.dtk 1.0 as D

D.ApplicationWindow {
    id: root

    visible: true
    width: (typeof initialWidth !== "undefined" && initialWidth > 0) ? initialWidth : 1480
    height: (typeof initialHeight !== "undefined" && initialHeight > 0) ? initialHeight : 920
    minimumWidth: 880
    minimumHeight: 600
    title: "Sonde — D-Bus 观察台"

    // ---- DTK 窗口（参照 dde-control-center 的 DccWindow.qml）----
    // D.DWindow.enabled 是关键：它告诉 DDE 这个窗口自己画标题栏，
    // 否则 DDE 的窗口框架会和下面的 D.TitleBar 各画一条 → 双标题栏。
    D.DWindow.enabled: true
    flags: Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowTitleHint
           | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint
    // 用不透明的主题色。不照抄 dde-control-center 的
    // `color: "transparent"` + StyledBehindWindowBlur —— 那是它刻意做毛玻璃，
    // 而且它不用 header:，模糊层能盖住整窗；用 header: 时模糊层只盖内容区，
    // 标题栏那条会没有背景、直接透出桌面。
    color: theme.bg

    // 共享状态
    property string busName: "session"
    property var selectedNode: null

    onBusNameChanged: {
        if (tree.service !== "")
            tree.setService(root.busName, tree.service)
    }

    Component.onCompleted: {
        if (typeof initialBus !== "undefined" && initialBus !== "")
            root.busName = initialBus
        if (typeof initialService !== "undefined" && initialService !== "")
            tree.setService(root.busName, initialService)

        if (typeof demoMode !== "undefined" && demoMode) {
            watchPane.expanded = true
            bridge.startMonitor(root.busName)
            bridge.addWatch("service", root.busName, "org.freedesktop.DBus", "", "", "")

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

    // ---------------------------------------------------------------- DTK 标题栏
    // 主题切换由 DTK 标题栏的 ThemeMenu 内置（浅色/深色/跟随系统），
    // 不再需要自己做一个按钮。
    header: D.TitleBar {
        id: titleBar
        title: root.title
        implicitHeight: 40
        // embedMode 默认为 !DWindow.enabled，这里显式写出来：
        // false 表示"标题栏自己画窗口按钮"，不再依赖窗口管理器
        embedMode: false
        autoHideOnFullscreen: true
        focus: true

        // 标题栏左侧自定义区：总线选择
        // （注意不能用 content——那个槽默认就是标题组件，占掉就没标题了）
        leftContent: Component {
            RowLayout {
                spacing: 8

                Label {
                    text: "Sonde"
                    color: theme.accent
                    font.bold: true
                    font.pixelSize: 14
                    Layout.leftMargin: 6
                }
                Label {
                    text: "总线"
                    color: theme.textDim
                    font.pixelSize: 12
                }
                D.ComboBox {
                    implicitHeight: 28
                    model: ["session", "system"]
                    currentIndex: root.busName === "system" ? 1 : 0
                    implicitWidth: 122
                    onActivated: root.busName = currentText
                }
                Label {
                    // 窄窗口时藏起来，否则会和标题栏居中的标题文字重叠
                    visible: bridge.monitoring && root.width > 760
                    text: "监听中 · " + bridge.total
                    color: theme.ok
                    font.pixelSize: 11
                }
                Label {
                    visible: !bridge.monitoring && tree.service !== "" && root.width > 1000
                    text: tree.service
                    color: theme.textDim
                    font.family: "monospace"
                    font.pixelSize: 11
                }
            }
        }

        // 菜单不用自己给：DTK 标题栏默认就是
        // ThemeMenu（浅色/深色/跟随系统）+ 帮助 + 关于 + 退出
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
                SplitView.preferredWidth: 276
                SplitView.minimumWidth: 100
                bus: root.busName
                onServiceActivated: (dest) => {
                    tree.setService(root.busName, dest)
                    root.selectedNode = null
                }
            }

            TreePane {
                id: treePane
                SplitView.fillWidth: true
                SplitView.minimumWidth: 120
                onNodeSelected: (row) => { root.selectedNode = row }
                onReadPropertyRequested: (n) => detailPane.readProperty(n)
            }

            DetailPane {
                id: detailPane
                SplitView.preferredWidth: 440
                SplitView.minimumWidth: 200
                node: root.selectedNode
                bus: root.busName
            }
        }

        WatchPane {
            id: watchPane
            Layout.fillWidth: true
            bus: root.busName
        }
    }
}
