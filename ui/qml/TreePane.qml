import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.deepin.dtk 1.0 as D
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

    function activate(n) {
        root.selectedId = n.id !== undefined ? n.id : ""
        root.nodeSelected(n)
    }

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

    function esc(t) {
        return ("" + t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    /// 签名的纯文本形式（参数 + 返回值），整体用一种颜色显示
    function sigPlain(m) {
        var parts = []
        if (m.argText !== undefined && m.argText !== "")
            parts.push(m.argText)
        if (m.retText !== undefined && m.retText !== "")
            parts.push(m.retText)
        if (parts.length === 0)
            return (m.detail !== undefined) ? m.detail : ""
        return parts.join("  ")
    }

    function buildTooltip(n) {
        var s = K.label(n.kind) + "   " + n.name + "\n"
        if (n.argText) s += "参数:  " + n.argText + "\n"
        if (n.retText) s += "返回:  " + n.retText + "\n"
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
            implicitHeight: 36
            color: theme.surfaceAlt

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                spacing: 6

                Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 40
                    text: tree.service === "" ? "对象树" : tree.service
                    color: theme.text
                    font.bold: true
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                }

                TextField {
                    Layout.preferredWidth: 130
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: 150
                    Layout.fillWidth: true
                    implicitHeight: 26
                    placeholderText: "过滤本树"
                    font.pixelSize: 11
                    onTextChanged: tree.filter = text
                }

                CheckBox {
                    text: "精简"
                    implicitHeight: 26
                    checked: tree.hideStandard
                    onToggled: tree.hideStandard = checked
                    font.pixelSize: 11
                    ToolTip.visible: hovered
                    ToolTip.text: "隐藏 org.freedesktop.DBus.* 标准接口"
                }

                // 展开/折叠/定位 这些收进菜单，窄面板才放得下
                D.ToolButton {
                    text: "⋯"
                    implicitWidth: 28
                    implicitHeight: 24
                    enabled: tree.service !== ""
                    onClicked: treeMenu.popup()
                    ToolTip.visible: hovered
                    ToolTip.text: "更多操作"
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

                // 双击：属性直接读值；其余节点展开/收起。
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

                // 纯文本 Row + 显式宽度：**elide 对 Text.RichText 无效**，
                // 富文本标签永远不会省略、只能被父级硬裁。
                // 所以拆成两个纯文本 Label（名称 / 签名），签名整体用强调色，
                // 名称宽度用 TextMetrics 量出来，两者都能正确省略。
                contentItem: Row {
                    id: rowContent
                    spacing: 6

                    // 量名称宽度（非 Item，Row 会忽略）
                    TextMetrics {
                        id: nameMetrics
                        font.family: "monospace"
                        font.pixelSize: 12
                        text: row.modelData.name
                    }
                    TextMetrics {
                        id: badgeMetrics
                        font.family: "monospace"
                        font.pixelSize: 9
                        font.bold: true
                        text: K.shortLabel(row.modelData.kind)
                    }

                    readonly property real avail: Math.max(0, row.width - row.leftPadding
                                                          - row.rightPadding
                                                          - arrowItem.width - 12
                                                          - (badgeMetrics.advanceWidth + 10))

                    Item {
                        id: arrowItem
                        width: 14
                        height: row.height
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
                        id: badgeRect
                        width: badgeMetrics.advanceWidth + 10
                        height: 16
                        y: (row.height - height) / 2
                        radius: 2
                        color: "transparent"
                        border.width: 1
                        border.color: K.colorFor(theme, row.modelData.kind)
                        Label {
                            anchors.centerIn: parent
                            text: K.shortLabel(row.modelData.kind)
                            color: K.colorFor(theme, row.modelData.kind)
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }

                    // 名称：最多占一半，先省略它还是签名由宽度决定
                    Label {
                        id: nameLabel
                        width: Math.max(36, Math.min(nameMetrics.advanceWidth + 2,
                                                     rowContent.avail * 0.55))
                        height: row.height
                        verticalAlignment: Text.AlignVCenter
                        text: row.modelData.name
                        color: theme.text
                        elide: Text.ElideRight
                        font.family: "monospace"
                        font.pixelSize: 12
                    }

                    // 签名（参数 + 返回值）：整体强调色，占剩下的宽度
                    Label {
                        width: Math.max(0, rowContent.avail - nameLabel.width
                                           - rowContent.spacing)
                        height: row.height
                        verticalAlignment: Text.AlignVCenter
                        text: root.sigPlain(row.modelData)
                        color: theme.accent
                        elide: Text.ElideRight
                        font.family: "monospace"
                        font.pixelSize: 11
                    }
                }

                ToolTip.visible: hovered
                ToolTip.delay: 900
                ToolTip.text: root.buildTooltip(row.modelData)
            }
        }
    }

    // ------------------------------------------------------------------ 头部菜单
    Menu {
        id: treeMenu
        MenuItem {
            text: "定位到本服务的对象"
            enabled: tree.service !== ""
            onTriggered: tree.locateService()
        }
        MenuItem {
            text: "全部展开"
            enabled: tree.service !== ""
            onTriggered: tree.expandAll()
        }
        MenuItem {
            text: "全部折叠"
            enabled: tree.service !== ""
            onTriggered: tree.collapseAll()
        }
        MenuSeparator {}
        MenuItem {
            text: "重新内省"
            enabled: tree.service !== ""
            onTriggered: tree.refresh()
        }
    }

    // ------------------------------------------------------------------ 右键菜单
    Menu {
        id: nodeMenu

        MenuItem {
            text: "加入过滤条件"
            visible: root.menuTarget !== null && root.menuTarget.kind !== "arg"
            onTriggered: {
                var n = root.menuTarget
                msgFilter.addQuery(K.filterTerm(n.kind, n.dest, n.path, n.iface, n.member))
            }
        }
        MenuItem {
            text: "读取该属性"
            visible: root.menuTarget !== null && root.menuTarget.kind === "property"
            onTriggered: root.readPropertyRequested(root.menuTarget)
        }
        MenuItem {
            text: root.menuTarget !== null && root.menuTarget.expanded ? "折叠" : "展开"
            visible: root.menuTarget !== null && root.menuTarget.kind !== "arg"
            onTriggered: tree.toggle(root.menuTarget.id)
        }
        MenuSeparator {}
        MenuItem {
            text: "复制名称"
            onTriggered: clip.put(root.menuTarget ? root.menuTarget.name : "")
        }
        MenuItem {
            text: "复制签名"
            visible: root.menuTarget !== null && root.menuTarget.argText !== ""
            onTriggered: clip.put(root.menuTarget.argText + " " + root.menuTarget.retText)
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
