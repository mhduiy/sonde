import QtQuick
import QtQuick.Controls
import org.deepin.dtk 1.0 as D
import QtQuick.Layouts
import "kinds.js" as K

/// 右栏：选中节点的详情。
/// 方法给参数编辑器，属性给读取（可轮询）+ 写入，信号给签名和加监听入口。
Rectangle {
    id: root

    property var node: null
    property string bus: "session"

    // 属性读取
    property var propRows: []
    property var propNode: null
    property string propError: ""
    property double propLastId: 0
    property string propName: ""
    property string propReadAt: ""
    property int pollMs: 0

    // 属性写入
    property string writeError: ""
    property bool writeOk: false
    property double writeLastId: 0

    color: theme.surface

    readonly property bool isProperty: node !== null && node.kind === "property"
    readonly property bool readable: isProperty
                                     && (node.access === "" || node.access.indexOf("read") >= 0)
    readonly property bool writable: isProperty
                                     && (node.access || "").indexOf("write") >= 0

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
        if (!n)
            return
        root.propName = n.member
        root.propError = ""
        root.propRows = []
        root.propLastId = bridge.callGetProperty(n.bus || root.bus, n.dest, n.path,
                                                n.iface, n.member)
    }

    function writeProperty(n, value) {
        if (!n)
            return
        root.writeError = ""
        root.writeOk = false
        root.writeLastId = bridge.callSetProperty(n.bus || root.bus, n.dest, n.path,
                                                 n.iface, n.member, n.argType, value)
    }

    /// 自检：把选中的方法填一个能跑通的值并发出去
    function demoRun(seed) {
        if (!callForm.fillFirstString(seed))
            callForm.fillFirstRecord("demo", seed)
        callForm.invoke()
    }

    onNodeChanged: {
        propError = ""
        propRows = []
        propReadAt = ""
        writeError = ""
        writeOk = false
        pollMs = 0
    }

    Connections {
        target: bridge
        function onPropertyRead(id, node, iface, name, error) {
            if (id !== root.propLastId)
                return
            root.propError = error
            root.propRows = (error === "" && node && Object.keys(node).length > 0)
                            ? bridge.flattenNodes([node]) : []
            root.propNode = (error === "" && node && Object.keys(node).length > 0) ? node : null
            root.propReadAt = K.clockOf(Date.now() * 1000)
        }
        function onPropertyWritten(id, ok, error) {
            if (id !== root.writeLastId)
                return
            root.writeOk = ok
            root.writeError = error
            if (ok && root.readable)
                root.readProperty(root.node) // 写完立刻回读，确认新值
        }
    }

    // 属性轮询
    Timer {
        interval: Math.max(200, root.pollMs)
        repeat: true
        running: root.pollMs > 0 && root.readable
        onTriggered: root.readProperty(root.node)
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

                    D.ToolButton {
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
            text: "在中间的树里点一个节点\n\n"
                  + "· 双击能展开/收起；双击属性会直接读值\n"
                  + "· 方法可以在这里填参数直接调用\n"
                  + "· 属性可以读取（支持定时轮询）也可以写入\n"
                  + "· 信号可以加入监听列表"
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

                // ---- 属性：读取 + 轮询 + 写入 ----
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: root.isProperty

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

                    // 读取 + 轮询
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        D.Button {
                            text: "读取当前值"
                            enabled: root.readable
                            onClicked: root.readProperty(root.node)
                        }
                        Label { text: "定时读取"; color: theme.textDim; font.pixelSize: 11 }
                        D.ComboBox {
                            id: pollBox
                            Layout.preferredWidth: 104
                            model: ["关闭", "1 秒", "2 秒", "5 秒"]
                            enabled: root.readable
                            onActivated: {
                                var ms = [0, 1000, 2000, 5000]
                                root.pollMs = ms[currentIndex]
                                if (root.pollMs > 0)
                                    root.readProperty(root.node)
                            }
                        }
                        D.ToolButton {
                            visible: root.propRows.length > 0
                            text: "复制值"
                            implicitHeight: 22
                            onClicked: clip.put(JSON.stringify(root.propRows.length === 1
                                                               ? root.propRows[0].display
                                                               : root.propRows, null, 2))
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            visible: root.propReadAt !== ""
                            text: "读取于 " + root.propReadAt
                                  + (root.pollMs > 0 ? "（轮询中）" : "")
                            color: theme.textFaint
                            font.pixelSize: 10
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: root.propError !== ""
                        wrapMode: Text.WordWrap
                        text: root.propError !== "" ? ("✗  " + root.propError) : ""
                        color: theme.error
                        font.family: "monospace"
                        font.pixelSize: 11
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: root.propNode !== null

                        ValueOutput {
                            Layout.fillWidth: true
                            nodes: root.propNode ? [root.propNode] : []
                            maxHeight: 300
                        }
                    }

                    // 写入
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        visible: root.writable
                        implicitHeight: writeCol.implicitHeight + 16
                        color: theme.surfaceAlt
                        radius: 4

                        ColumnLayout {
                            id: writeCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            Label {
                                text: "写入新值（" + (root.node ? root.node.argType : "")
                                      + "，走 org.freedesktop.DBus.Properties.Set）"
                                color: theme.textDim
                                font.bold: true
                                font.pixelSize: 11
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                D.TextField {
                                    id: writeField
                                    Layout.fillWidth: true
                                    placeholderText: "新值"
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                }
                                D.Button {
                                    text: "写入"
                                    enabled: writeField.text !== ""
                                    onClicked: root.writeProperty(root.node, writeField.text)
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: root.writeError !== ""
                                wrapMode: Text.WordWrap
                                text: root.writeError !== "" ? ("✗  " + root.writeError) : ""
                                color: theme.error
                                font.family: "monospace"
                                font.pixelSize: 11
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: root.writeError === "" && root.writeOk
                                text: "✓  写入成功（已回读确认）"
                                color: theme.ok
                                font.family: "monospace"
                                font.pixelSize: 11
                            }
                        }
                    }
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
                              + "  · 双击属性 → 直接读取当前值\n"
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

    Clip { id: clip }
}
