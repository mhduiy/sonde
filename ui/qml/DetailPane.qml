import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "kinds.js" as K

/// 右栏：选中节点的详情。按节点类型给出不同的内容——
/// 方法给参数编辑器，属性给读取按钮，信号给签名和加监听入口。
Rectangle {
    id: root

    property var node: null
    property string bus: "session"

    property var propValue: null
    property var propRows: []
    property string propError: ""
    property double propLastId: 0
    property string propName: ""

    color: theme.surface

    function watchKindOf(n) {
        if (!n)
            return ""
        if (n.kind === "method" || n.kind === "signal")
            return "member"
        if (n.kind === "property")
            return "property"
        if (n.kind === "interface")
            return "interface"
        return "path"
    }

    function addCurrentWatch() {
        if (!root.node)
            return
        bridge.addWatch(watchKindOf(root.node), node.bus || root.bus, root.node.dest,
                        root.node.path, root.node.iface, root.node.member)
    }

    function readProperty(n) {
        root.propTarget = n
        root.propName = n.member
        root.propError = ""
        root.propValue = null
        root.propRows = []
        root.propLastId = bridge.callGetProperty(n.bus || root.bus, n.dest, n.path,
                                                n.iface, n.member)
    }

    /// 自检：把选中的方法填一个能跑通的值并发出去
    function demoRun(seed) {
        callForm.fillFirstString(seed)
        callForm.invoke()
    }

    onNodeChanged: {
        propError = ""
        propValue = null
        propRows = []
    }

    Connections {
        target: bridge
        function onPropertyRead(id, node, iface, name, error) {
            if (id !== root.propLastId)
                return
            root.propError = error
            root.propValue = node
            root.propRows = (error === "" && node && Object.keys(node).length > 0)
                            ? bridge.flattenNodes([node]) : []
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------------------------------------------------- 标题
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: root.node ? 56 : 34
            color: theme.surfaceAlt

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        visible: root.node !== null
                        implicitWidth: kindBadge.implicitWidth + 10
                        implicitHeight: 16
                        radius: 2
                        color: "transparent"
                        border.width: 1
                        border.color: root.node ? K.colorFor(theme, root.node.kind) : theme.border
                        Label {
                            id: kindBadge
                            anchors.centerIn: parent
                            text: root.node ? K.shortLabel(root.node.kind) : ""
                            color: root.node ? K.colorFor(theme, root.node.kind) : theme.textDim
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: root.node ? root.node.name : "详情"
                        color: theme.text
                        font.bold: true
                        font.family: "monospace"
                        font.pixelSize: 13
                        elide: Text.ElideMiddle
                    }

                    ToolButton {
                        visible: root.node !== null && root.node.kind !== "arg"
                        text: "＋ 监听"
                        implicitHeight: 24
                        onClicked: root.addCurrentWatch()
                        ToolTip.visible: hovered
                        ToolTip.text: "把这个节点加入监听列表"
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: root.node !== null
                    text: root.node
                          ? (root.node.path + (root.node.iface ? "   " + root.node.iface : "")
                             + (root.node.member ? " . " + root.node.member : ""))
                          : ""
                    color: theme.textFaint
                    font.family: "monospace"
                    font.pixelSize: 10
                    elide: Text.ElideMiddle
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
        Label {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.node === null
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            text: "在中间的树里点一个节点\n\n方法可以在这里填参数直接调用；\n属性可以读取当前值；\n信号可以加入监听列表。"
            color: theme.textFaint
            font.pixelSize: 12
        }

        // ---------------------------------------------------------- 内容
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.node !== null
            clip: true

            ColumnLayout {
                width: root.width - 24
                x: 12
                spacing: 10

                // ---- 方法：参数编辑器 ----
                CallForm {
                    id: callForm
                    Layout.fillWidth: true
                    visible: root.node !== null && root.node.kind === "method"
                    bus: root.node ? (root.node.bus || root.bus) : root.bus
                    dest: root.node ? root.node.dest : ""
                    path: root.node ? root.node.path : ""
                    iface: root.node ? root.node.iface : ""
                    member: root.node ? root.node.member : ""
                    sig: root.node ? root.node.inSig : ""
                }

                // ---- 信号 ----
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.node !== null && root.node.kind === "signal"

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 12

                        Label { text: "参数签名"; color: theme.textDim; font.pixelSize: 11 }
                        Label {
                            text: root.node && root.node.inSig !== "" ? root.node.inSig : "（无）"
                            color: theme.valStr
                            font.family: "monospace"
                            font.pixelSize: 12
                        }
                        Label { text: "发出者"; color: theme.textDim; font.pixelSize: 11 }
                        Label {
                            text: root.node ? root.node.dest : ""
                            color: theme.text
                            font.family: "monospace"
                            font.pixelSize: 12
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "展开树里的这个信号可以看到每个参数的名称与类型。\n"
                              + "点右上角「＋ 监听」，或右键这个信号加入监听列表，"
                              + "之后总线上每次发出它都会出现在下方的监听面板里。"
                        color: theme.textFaint
                        font.pixelSize: 11
                    }
                }

                // ---- 属性 ----
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: root.node !== null && root.node.kind === "property"

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 12

                        Label { text: "类型"; color: theme.textDim; font.pixelSize: 11 }
                        Label {
                            text: root.node ? root.node.argType : ""
                            color: theme.valNum
                            font.family: "monospace"
                            font.pixelSize: 12
                        }
                        Label { text: "访问"; color: theme.textDim; font.pixelSize: 11 }
                        Label {
                            text: root.node ? root.node.access : ""
                            color: theme.text
                            font.family: "monospace"
                            font.pixelSize: 12
                        }
                    }

                    RowLayout {
                        spacing: 8
                        Button {
                            text: "读取当前值"
                            enabled: root.node !== null
                                     && (root.node.access === "" || root.node.access.indexOf("read") >= 0)
                            onClicked: root.readProperty(root.node)
                        }
                        Label {
                            visible: root.propError !== ""
                            text: "✗  " + root.propError
                            color: theme.error
                            font.family: "monospace"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Label {
                            visible: root.propError === "" && root.propRows.length > 0
                            text: "✓  " + root.propName
                            color: theme.ok
                            font.family: "monospace"
                            font.pixelSize: 11
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        visible: root.propRows.length > 0

                        Repeater {
                            model: root.propRows
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8

                                Item {
                                    Layout.preferredWidth: modelData.depth * 14
                                    Layout.fillHeight: true
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.display
                                    color: K.valueColor(theme, modelData.kind, modelData.composite)
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
                        }
                    }
                }

                // ---- 接口 ----
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.node !== null && root.node.kind === "interface"

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "接口 " + (root.node ? root.node.name : "") + "\n\n"
                              + "在树里展开可以看到它的方法、信号和属性：\n"
                              + "  · 点方法 → 在这里填参数直接调用\n"
                              + "  · 点属性 → 读取当前值\n"
                              + "  · 点信号 → 加入监听列表看实时触发\n\n"
                              + "「＋ 监听」会监听这个接口下的全部消息。"
                        color: theme.textDim
                        font.pixelSize: 12
                    }
                }

                // ---- 路径 ----
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.node !== null && root.node.kind === "path"

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "对象路径 " + (root.node ? root.node.path : "") + "\n\n"
                              + "展开它可以看到这个路径下的接口；\n"
                              + "如果下面还有子路径，也会一并列出。\n\n"
                              + "「＋ 监听」会监听这个路径上的全部消息。"
                        color: theme.textDim
                        font.pixelSize: 12
                    }
                }

                // ---- 参数节点 ----
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.node !== null && root.node.kind === "arg"

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 12

                        Label { text: "类型"; color: theme.textDim; font.pixelSize: 11 }
                        Label {
                            text: root.node ? root.node.argType : ""
                            color: theme.valBool
                            font.family: "monospace"
                            font.pixelSize: 12
                        }
                        Label { text: "方向"; color: theme.textDim; font.pixelSize: 11 }
                        Label {
                            text: root.node
                                  ? (root.node.access === "out" ? "输出 (out)" : "输入 (in)")
                                  : ""
                            color: theme.text
                            font.family: "monospace"
                            font.pixelSize: 12
                        }
                        Label { text: "所属"; color: theme.textDim; font.pixelSize: 11 }
                        Label {
                            text: root.node ? (root.node.iface + "." + root.node.member) : ""
                            color: theme.textDim
                            font.family: "monospace"
                            font.pixelSize: 11
                        }
                    }
                }

                Item { Layout.preferredHeight: 12 }
            }
        }
    }

    // 给 readProperty 用的临时目标
    property var propTarget: null
    Clip { id: clip }
}
