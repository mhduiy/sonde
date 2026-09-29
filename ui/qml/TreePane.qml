import QtQuick
import QtQuick.Controls
import org.deepin.dtk 1.0 as D
import QtQuick.Layouts
import "kinds.js" as K

/// 中栏：对象树（服务 → 路径 → 接口 → 方法/信号/属性）——新界面的主体
Rectangle {
    id: root

    /// 当前选中的节点 id（由本组件自己维护，供高亮用）
    property string selectedId: ""
    /// 右键菜单当前指向的节点
    property var menuTarget: null

    signal nodeSelected(var row)
    signal readPropertyRequested(var node)

    color: theme.surface

    /// 上次滚动到的 focus 节点，避免用户手动展开时被反复拽走
    property string lastFocus: ""

    function scrollToFocus() {
        var rows = tree.rows
        for (var i = 0; i < rows.length; ++i) {
            if (rows[i].id === tree.focusId) {
                list.positionViewAtIndex(i, ListView.BeginVisible)
                return
            }
        }
    }

    Connections {
        target: tree
        function onRowsChanged() {
            if (tree.focusId !== "" && tree.focusId !== root.lastFocus) {
                root.lastFocus = tree.focusId
                Qt.callLater(root.scrollToFocus)
            }
        }
    }

    function activate(n) {
        root.selectedId = n.id !== undefined ? n.id : ""
        root.nodeSelected(n)
    }

    function buildTooltip(n) {
        var s = K.label(n.kind) + "   " + n.name + "\n"
        if (n.path) s += "路径:  " + n.path + "\n"
        if (n.iface) s += "接口:  " + n.iface + "\n"
        if (n.member) s += "成员:  " + n.member + "\n"
        if (n.argType) s += "类型:  " + n.argType + "\n"
        if (n.access) s += "方向/访问:  " + n.access + "\n"
        return s + "\n右键可加入监听列表"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------------------------------------------------- 标题栏
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
                    text: tree.service === "" ? "对象树" : tree.service
                    color: theme.text
                    font.bold: true
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 360
                }
                Rectangle {
                    visible: tree.service !== ""
                    implicitWidth: 76
                    implicitHeight: 15
                    radius: 2
                    color: theme.accentSoft
                    Label {
                        anchors.centerIn: parent
                        text: tree.bus
                        color: theme.accent
                        font.pixelSize: 9
                    }
                }

                Item { Layout.fillWidth: true }

                D.TextField {
                    Layout.preferredWidth: 150
                    implicitHeight: 24
                    placeholderText: "过滤本树"
                    font.pixelSize: 11
                    onTextChanged: tree.filter = text
                }

                D.ToolButton {
                    text: "定位"
                    implicitHeight: 24
                    enabled: tree.service !== ""
                    onClicked: tree.locateService()
                    ToolTip.visible: hovered
                    ToolTip.text: "跳到与服务名对应的对象路径（例如 org.deepin.dde.Timedate1 → /org/deepin/dde/Timedate1）"
                }
                D.CheckBox {
                    implicitHeight: 26
                    text: "精简"
                    checked: tree.hideStandard
                    onToggled: tree.hideStandard = checked
                    font.pixelSize: 11
                    ToolTip.visible: hovered
                    ToolTip.text: "隐藏 org.freedesktop.DBus.* 标准接口，只留下服务自己的接口"
                }
                D.ToolButton {
                    text: "展开"
                    implicitHeight: 24
                    enabled: tree.service !== ""
                    onClicked: tree.expandAll()
                }
                D.ToolButton {
                    text: "折叠"
                    implicitHeight: 24
                    enabled: tree.service !== ""
                    onClicked: tree.collapseAll()
                }
                D.ToolButton {
                    text: "⟳"
                    implicitWidth: 26
                    implicitHeight: 24
                    enabled: tree.service !== ""
                    onClicked: tree.refresh()
                    ToolTip.visible: hovered
                    ToolTip.text: "重新内省这个服务"
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: theme.border
            }
        }

        // ---------------------------------------------------------- 空状态
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tree.service === "" || tree.rows.length === 0
            spacing: 8

            Item { Layout.fillHeight: true }

            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: tree.service === ""
                      ? "从左侧选一个服务\n\nSonde 会把它的对象路径、接口、方法、信号、属性层层展开"
                      : (tree.error !== "" ? ("⚠   " + tree.error)
                                           : "这个服务没有提供内省信息")
                color: tree.error !== "" ? theme.error : theme.textFaint
                wrapMode: Text.WordWrap
                font.pixelSize: 13
            }

            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: tree.service !== "" && tree.error !== ""
                text: "可以右键服务「加入监听列表」，仍然能看到它的消息。"
                color: theme.textFaint
                font.pixelSize: 12
            }

            Item { Layout.fillHeight: true }
        }

        // ---------------------------------------------------------- 树
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tree.rows.length > 0
            clip: true
            model: tree.rows
            ScrollBar.vertical: ScrollBar {}
            reuseItems: true
            cacheBuffer: 2000

            delegate: ItemDelegate {
                id: row
                required property var modelData

                width: list.width
                height: 28
                leftPadding: 6 + modelData.depth * 15
                rightPadding: 8

                highlighted: modelData.id === root.selectedId
                background: Rectangle {
                    color: row.highlighted ? theme.selected
                                           : (row.hovered ? theme.hover : "transparent")
                }

                onClicked: {
                    root.menuTarget = row.modelData
                    root.activate(row.modelData)
                }

                // 双击：属性直接读值；其余节点（路径/接口/方法/信号）都是展开/收起。
                // 注意不能用 hasChildren 判断——未加载的节点 children 为空，
                // 那样双击就毫无反应（用户会以为"点不开"）。
                onDoubleClicked: {
                    root.menuTarget = row.modelData
                    root.activate(row.modelData)
                    if (row.modelData.kind === "property")
                        root.readPropertyRequested(row.modelData)
                    else if (row.modelData.kind !== "arg")
                        tree.toggle(row.modelData.id)
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: {
                        root.menuTarget = row.modelData
                        root.activate(row.modelData)
                        nodeMenu.popup()
                    }
                }

                contentItem: RowLayout {
                    spacing: 6

                    Item {
                        implicitWidth: 14
                        implicitHeight: 20
                        Label {
                            anchors.centerIn: parent
                            text: row.modelData.hasChildren
                                  ? (row.modelData.expanded ? "▾" : "▸") : ""
                            color: theme.textDim
                            font.pixelSize: 11
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: row.modelData.kind !== "arg"
                            onClicked: tree.toggle(row.modelData.id)
                        }
                    }

                    Rectangle {
                        implicitWidth: typeBadge.implicitWidth + 10
                        implicitHeight: 16
                        radius: 2
                        color: "transparent"
                        border.width: 1
                        border.color: K.colorFor(theme, row.modelData.kind)
                        Label {
                            id: typeBadge
                            anchors.centerIn: parent
                            text: K.shortLabel(row.modelData.kind)
                            color: K.colorFor(theme, row.modelData.kind)
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }

                    Label {
                        Layout.maximumWidth: 300
                        text: row.modelData.name
                        color: theme.text
                        font.family: "monospace"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    // 参数直接写在签名括号里，用另一个颜色标出来
                    Label {
                        visible: row.modelData.argText !== ""
                        text: row.modelData.argText
                        color: theme.accent
                        font.family: "monospace"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.maximumWidth: 320
                    }
                    Label {
                        visible: row.modelData.retText !== ""
                        text: row.modelData.retText
                        color: theme.textDim
                        font.family: "monospace"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.maximumWidth: 240
                    }
                    // 属性 / 路径这类没有参数拆分的，仍然用 detail
                    Label {
                        visible: row.modelData.argText === "" && row.modelData.retText === ""
                        text: row.modelData.detail
                        color: theme.textDim
                        font.family: "monospace"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.maximumWidth: 240
                    }

                    // 吸收剩余空间，保证上面这些是"紧跟名字"而不是被推到右边
                    Item { Layout.fillWidth: true }
                }

                ToolTip.visible: hovered
                ToolTip.delay: 900
                ToolTip.text: root.buildTooltip(row.modelData)
            }
        }
    }

    // ------------------------------------------------------------------ 右键菜单
    Menu {
        id: nodeMenu

        MenuItem {
            text: "加入监听列表"
            visible: root.menuTarget !== null && root.menuTarget.kind !== "arg"
            onTriggered: {
                var n = root.menuTarget
                var kind = "path"
                if (n.kind === "interface") kind = "interface"
                else if (n.kind === "method") kind = "member"
                else if (n.kind === "signal") kind = "member"
                else if (n.kind === "property") kind = "property"
                bridge.addWatch(kind, n.bus, n.dest, n.path, n.iface, n.member)
            }
        }
        MenuItem {
            text: "读取该属性"
            visible: root.menuTarget !== null && root.menuTarget.kind === "property"
            onTriggered: root.readPropertyRequested(root.menuTarget)
        }
        MenuItem {
            text: root.menuTarget !== null && root.menuTarget.expanded ? "折叠" : "展开"
            visible: root.menuTarget !== null && root.menuTarget.hasChildren
            onTriggered: tree.toggle(root.menuTarget.id)
        }
        MenuSeparator {}
        MenuItem {
            text: "复制名称"
            onTriggered: clip.put(root.menuTarget ? root.menuTarget.name : "")
        }
        MenuItem {
            text: "复制路径"
            visible: root.menuTarget !== null && root.menuTarget.path !== ""
            onTriggered: clip.put(root.menuTarget ? root.menuTarget.path : "")
        }
        MenuItem {
            text: "复制「接口.成员」"
            visible: root.menuTarget !== null && root.menuTarget.iface !== ""
                     && root.menuTarget.member !== ""
            onTriggered: clip.put(root.menuTarget.iface + "." + root.menuTarget.member)
        }
    }

    Clip { id: clip }
}
