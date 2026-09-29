import QtQuick
import QtQuick.Controls
import org.deepin.dtk 1.0 as D
import QtQuick.Layouts
import "kinds.js" as K

/// 签名驱动的参数编辑器 + 调用。
///
/// 表单完全由 D-Bus 签名生成（Rust 的 type_tree），不用手写 GVariant 文本。
///
/// **关键点（踩过的坑）**：QML 把 JS 数组的元素交给 Repeater delegate 时，
/// `modelData` 是**副本**，`modelData.node.text = x` 写不回去——表现就是
/// 界面上填了参数，实际发出去却是空参数。所以这里 delegate 只拿 `index`，
/// 通过 `rowAt(index)` 实时取真正的行对象，写回用 `setRowText(index, ...)`。
ColumnLayout {
    id: root

    property string bus: "session"
    property string dest: ""
    property string path: ""
    property string iface: ""
    property string member: ""
    property string sig: ""

    property var nodes: []
    property var rows: []
    property var result: null
    property var resultRows: []
    property bool busy: false
    property double lastId: 0
    /// rebuild 时自增，强制 delegate 重新读取行
    property int rev: 0

    spacing: 8

    function clone(x) {
        return JSON.parse(JSON.stringify(x))
    }

    function reset() {
        root.nodes = clone(bridge.typeTree(root.sig))
        root.result = null
        root.resultRows = []
        root.busy = false
        rebuild()
    }

    // ---- 行的实时读写（delegate 只能通过这两个函数碰数据）----
    function rowAt(i) {
        return root.rows[i]
    }
    function setRowText(i, t) {
        if (root.rows[i])
            root.rows[i].node.text = t
    }

    function isComposite(kind) {
        return kind === "array" || kind === "dict" || kind === "struct" || kind === "variant"
    }

    function rebuild() {
        var out = []
        for (var i = 0; i < root.nodes.length; ++i)
            walk(root.nodes[i], 0, "[" + i + "]", null, -1, out)
        root.rows = out
        root.rev = root.rev + 1
    }

    function walk(node, depth, label, parent, index, out) {
        if (!node)
            return
        var kind = node.kind || ""
        out.push({
            depth: depth, label: label, node: node, kind: kind,
            composite: isComposite(kind),
            parent: parent, index: index,
            removable: parent !== null && (parent.kind || "") !== "struct"
        })
        var items = node.items || []
        for (var i = 0; i < items.length; ++i) {
            var e = items[i]
            if (e.key !== undefined && e.val !== undefined) {
                out.push({
                    depth: depth + 1, label: "键", node: e.key,
                    kind: e.key.kind || "", composite: false,
                    parent: node, index: i, removable: true
                })
                walk(e.val, depth + 1, "值", node, i, out)
            } else if (e.node !== undefined) {
                var lbl = kind === "array" ? ("[" + i + "]")
                                           : (e.label !== undefined ? e.label : ("·" + i))
                walk(e.node, depth + 1, lbl, node, i, out)
            }
        }
    }

    function summaryOf(node) {
        var k = node.kind || ""
        var n = (node.items || []).length
        if (k === "array") return "[" + n + "]"
        if (k === "dict") return "{" + n + "}"
        if (k === "struct") return "(" + n + ")"
        if (k === "variant") {
            var inner = (node.items && node.items[0] && node.items[0].node)
                        ? node.items[0].node.kind : ""
            return "<" + inner + ">"
        }
        return node.text !== undefined ? ("" + node.text) : ""
    }

    function addChild(node) {
        if (node.kind === "array") {
            node.items = (node.items || []).concat([clone(node.elemTemplate)])
        } else if (node.kind === "dict") {
            node.items = (node.items || []).concat([{
                label: "", key: clone(node.keyTemplate), val: clone(node.valTemplate)
            }])
        }
        rebuild()
    }

    function removeChild(row) {
        if (row.parent && row.parent.items && row.index >= 0) {
            row.parent.items.splice(row.index, 1)
            rebuild()
        }
    }

    function applyVariant(node) {
        var s = (node.text || "s").trim()
        var t = clone(bridge.typeTree(s))
        if (t && t.length > 0)
            node.items = [{ label: "value", node: t[0] }]
        rebuild()
    }

    function invoke() {
        root.busy = true
        root.result = null
        root.resultRows = []
        root.lastId = bridge.call(root.bus, root.dest, root.path, root.iface,
                                  root.member, root.sig, root.nodes)
    }

    /// 自检用：给第一个空的字符串参数填个值（走和 delegate 相同的写回路径）
    function fillFirstString(v) {
        for (var i = 0; i < root.rows.length; ++i) {
            var n = root.rowAt(i).node
            if (n && n.kind === "str" && (n.text === undefined || n.text === "")) {
                root.setRowText(i, v)
                rebuild() // 让输入框回显填进去的值（setRowText 本身刻意不动 rev）
                return true
            }
        }
        return false
    }

    /// 当前参数树的 JSON 预览（排查"参数到底发出去了没有"）
    function argsJson() {
        return JSON.stringify(root.nodes)
    }

    onSigChanged: reset()
    onMemberChanged: reset()

    Connections {
        target: bridge
        function onCallFinished(id, res) {
            if (id !== root.lastId)
                return
            root.busy = false
            root.result = res
            root.resultRows = res.ok && res.args ? bridge.flattenNodes(res.args) : []
        }
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Label {
            text: "参数" + (root.sig === "" ? "（无）" : "（" + root.sig + "）")
            color: theme.textDim
            font.bold: true
            font.pixelSize: 11
        }
        Item { Layout.fillWidth: true }
        D.ToolButton {
            text: "复制参数"
            implicitHeight: 22
            visible: root.nodes.length > 0
            onClicked: clip.put(JSON.stringify(root.nodes, null, 2))
            ToolTip.visible: hovered
            ToolTip.text: "复制当前参数树的 JSON，方便确认参数到底长什么样"
        }
    }

    Label {
        Layout.fillWidth: true
        visible: root.rows.length === 0
        text: "该签名没有参数，直接发送即可。"
        color: theme.textFaint
        font.pixelSize: 11
    }

    // ---------------------------------------------------------- 参数编辑区
    ScrollView {
        Layout.fillWidth: true
        Layout.preferredHeight: root.rows.length === 0 ? 0
                              : Math.min(300, root.rows.length * 32 + 8)
        clip: true
        visible: root.rows.length > 0

        ColumnLayout {
            width: parent.width
            spacing: 3

            Repeater {
                model: root.rows.length
                delegate: RowLayout {
                    id: editRow
                    required property int index
                    // 依赖 rev，rebuild 后重新取到行
                    readonly property var row: { root.rev; return root.rowAt(index) }

                    Layout.fillWidth: true
                    spacing: 6

                    Item {
                        Layout.preferredWidth: editRow.row.depth * 14
                        Layout.fillHeight: true
                    }

                    Label {
                        Layout.preferredWidth: 74
                        text: editRow.row.label
                        color: theme.textFaint
                        font.family: "monospace"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    D.TextField {
                        Layout.fillWidth: true
                        visible: !editRow.row.composite && editRow.row.node.kind !== "variant"
                        text: editRow.row.node.text !== undefined
                              ? ("" + editRow.row.node.text) : ""
                        placeholderText: editRow.row.kind
                        font.family: "monospace"
                        font.pixelSize: 12
                        onTextEdited: root.setRowText(editRow.index, text)
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: editRow.row.node.kind === "variant"
                        D.TextField {
                            Layout.preferredWidth: 64
                            text: editRow.row.node.text || "s"
                            placeholderText: "内层签名"
                            font.family: "monospace"
                            font.pixelSize: 12
                            onEditingFinished: editRow.row.node.text = text
                        }
                        D.Button {
                            text: "应用"
                            implicitHeight: 26
                            onClicked: {
                                editRow.row.node.text = editRow.row.node.text || "s"
                                root.applyVariant(editRow.row.node)
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: root.summaryOf(editRow.row.node)
                            color: theme.accent
                            font.family: "monospace"
                            font.pixelSize: 11
                        }
                    }

                    Label {
                        visible: editRow.row.composite && editRow.row.node.kind !== "variant"
                        Layout.preferredWidth: 150
                        text: root.summaryOf(editRow.row.node)
                        color: theme.accent
                        font.family: "monospace"
                        font.pixelSize: 11
                    }

                    Label {
                        Layout.preferredWidth: 36
                        text: editRow.row.kind
                        color: theme.textFaint
                        font.family: "monospace"
                        font.pixelSize: 10
                    }

                    D.Button {
                        visible: editRow.row.node.kind === "array"
                                 || editRow.row.node.kind === "dict"
                        text: "＋"
                        implicitWidth: 30
                        implicitHeight: 26
                        onClicked: root.addChild(editRow.row.node)
                    }
                    D.Button {
                        visible: editRow.row.removable
                        text: "－"
                        implicitWidth: 30
                        implicitHeight: 26
                        onClicked: root.removeChild(editRow.row)
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- 发送 / 结果
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        D.Button {
            text: "发送调用"
            enabled: !root.busy && root.dest !== "" && root.member !== ""
            onClicked: root.invoke()
        }
        Label {
            visible: root.busy
            text: "调用中…"
            color: theme.textDim
            font.pixelSize: 12
        }
        Label {
            visible: root.result !== null && root.result.ok
            text: root.result
                  ? ("✓  返回签名: " + (root.result.signature === "" ? "（空）"
                                                                   : root.result.signature))
                  : ""
            color: theme.ok
            font.family: "monospace"
            font.pixelSize: 11
        }
        Item { Layout.fillWidth: true }
        D.ToolButton {
            visible: root.result !== null && root.result.ok
            text: "复制返回"
            implicitHeight: 22
            onClicked: clip.put(JSON.stringify(root.result, null, 2))
        }
    }

    Label {
        Layout.fillWidth: true
        visible: root.result !== null && !root.result.ok
        wrapMode: Text.WordWrap
        text: root.result ? ("✗  " + root.result.error) : ""
        color: theme.error
        font.family: "monospace"
        font.pixelSize: 11
    }

    // 结构化输出：表格 / JSON / 文本，自动识别挑默认页签
    ValueOutput {
        Layout.fillWidth: true
        visible: root.result !== null && root.result.ok
                 && root.result.args && root.result.args.length > 0
        nodes: (root.result && root.result.args) ? root.result.args : []
    }

    Clip { id: clip }
}
