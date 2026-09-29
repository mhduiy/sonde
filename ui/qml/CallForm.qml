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
    /// 用表格编辑的顶层参数下标 / 对应的形状信息
    property var tableIdx: []
    property var tableInfos: []

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

    function isScalarKind(kind) {
        return kind !== "" && !isComposite(kind)
    }

    /// 记录形态的顶层参数才用表格编辑：
    /// - dict 且值类型是标量（a{ss} / a{sv} 里的标量变体）
    /// - array 且元素是"字段全是标量"的 struct
    /// 其余（嵌套、复杂结构）继续走行式编辑器。
    function recordInfo(i) {
        var n = root.nodes[i]
        if (!n)
            return null
        if (n.kind === "dict") {
            var vt = n.valTemplate ? (n.valTemplate.kind || "") : ""
            var vScalar = root.isScalarKind(vt)
                || (vt === "variant" && n.valTemplate && n.valTemplate.items
                    && n.valTemplate.items[0] && n.valTemplate.items[0].node
                    && root.isScalarKind(n.valTemplate.items[0].node.kind || ""))
            if (!vScalar)
                return null
            return { kind: "dict", cols: ["键", "值"] }
        }
        if (n.kind === "array") {
            var et = n.elemTemplate
            if (!et || et.kind !== "struct")
                return null
            var fields = et.items || []
            var cols = []
            for (var f = 0; f < fields.length; ++f) {
                var fk = fields[f].node ? (fields[f].node.kind || "") : ""
                if (!root.isScalarKind(fk))
                    return null
                cols.push("" + f)
            }
            if (cols.length === 0)
                return null
            return { kind: "structArray", cols: cols }
        }
        return null
    }

    function recordRows(i) {
        root.rev // 依赖 rev，增删行后重新求值
        var n = root.nodes[i]
        return (n && n.items) ? n.items.length : 0
    }

    function cellWidth(info, c) {
        if (info && info.kind === "dict")
            return c === 0 ? 170 : 280
        return 108
    }

    function cellText(i, r, c) {
        root.rev // 依赖 rev：程序化填值后 rebuild 能回显，用户输入时不 rebuild 所以不打断焦点
        var n = root.nodes[i]
        if (!n || !n.items || !n.items[r])
            return ""
        if (n.kind === "dict") {
            var e = n.items[r]
            var node = (c === 0) ? e.key : e.val
            return node && node.text !== undefined ? ("" + node.text) : ""
        }
        var st = n.items[r].node
        var f = (st && st.items && st.items[c]) ? st.items[c].node : null
        return f && f.text !== undefined ? ("" + f.text) : ""
    }

    function setCellText(i, r, c, t) {
        var n = root.nodes[i]
        if (!n || !n.items || !n.items[r])
            return
        if (n.kind === "dict") {
            var e = n.items[r]
            var node = (c === 0) ? e.key : e.val
            if (node)
                node.text = t
            return
        }
        var st = n.items[r].node
        if (st && st.items && st.items[c] && st.items[c].node)
            st.items[c].node.text = t
    }

    function addRecordRow(i) {
        var n = root.nodes[i]
        if (!n)
            return
        addChild(n) // 复用：dict 推 key/val 模板，array 推 elemTemplate，内部会 rebuild
    }

    function removeRecordRow(i, r) {
        var n = root.nodes[i]
        if (!n || !n.items)
            return
        n.items.splice(r, 1)
        rebuild()
    }

    function rebuild() {
        // 先决定哪些顶层参数走"表格编辑"（记录形态），其余走行式编辑器
        var idx = []
        var infos = []
        for (var i = 0; i < root.nodes.length; ++i) {
            var ri = root.recordInfo(i)
            if (ri) {
                idx.push(i)
                infos.push(ri)
            }
        }
        root.tableIdx = idx
        root.tableInfos = infos

        var out = []
        for (var j = 0; j < root.nodes.length; ++j) {
            if (idx.indexOf(j) >= 0)
                continue // 这个参数交给表格渲染
            walk(root.nodes[j], 0, "[" + j + "]", null, -1, out)
        }
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

    /// 自检用：给第一个记录形态参数加一行（走和表格相同的写回路径）
    function fillFirstRecord(key, value) {
        if (root.tableIdx.length === 0)
            return false
        var p = root.tableIdx[0]
        root.addRecordRow(p)
        var r = root.recordRows(p) - 1
        if (root.tableInfos[0].kind === "dict") {
            root.setCellText(p, r, 0, key)
            root.setCellText(p, r, 1, value)
        } else {
            root.setCellText(p, r, 0, value)
        }
        rebuild() // 让单元格回显（setCellText 本身不动 rev，避免打断用户输入）
        return true
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
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: "参数" + (root.sig === "" ? "（无）" : "（" + root.sig + "）")
            color: theme.textDim
            font.bold: true
            font.pixelSize: 11
        }
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
        visible: root.rows.length === 0 && root.tableIdx.length === 0
        text: "该签名没有参数，直接发送即可。"
        color: theme.textFaint
        font.pixelSize: 11
    }

    // ---------------------------------------------------------- 记录形态参数：表格编辑
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10
        visible: root.tableIdx.length > 0

        Repeater {
            model: root.tableIdx
            delegate: ColumnLayout {
                id: tblock
                required property int index
                readonly property int p: root.tableIdx[index]
                readonly property var info: root.tableInfos[index]

                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Label {
                        text: "[" + tblock.p + "]   "
                              + (root.nodes[tblock.p] ? root.nodes[tblock.p].kind : "")
                              + "   " + (root.nodes[tblock.p] ? root.nodes[tblock.p].sig : "")
                              + "   （表格编辑）"
                        color: theme.textDim
                        font.bold: true
                        font.family: "monospace"
                        font.pixelSize: 11
                    }
                    Item { Layout.fillWidth: true }
                    D.ToolButton {
                        text: "＋ 加一行"
                        implicitHeight: 22
                        onClicked: root.addRecordRow(tblock.p)
                    }
                }

                Flickable {
                    Layout.fillWidth: true
                    implicitHeight: 24
                    contentWidth: Math.max(width, rowHeader.width)
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                    Row {
                        id: rowHeader
                        Repeater {
                            model: tblock.info.cols
                        delegate: Rectangle {
                            required property int index
                            required property var modelData
                            width: root.cellWidth(tblock.info, index)
                            height: 22
                            color: theme.surfaceAlt
                            Rectangle {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                width: 1
                                height: parent.height + 1
                                color: theme.border
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: theme.border
                            }
                            Label {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                verticalAlignment: Text.AlignVCenter
                                text: modelData
                                color: theme.textDim
                                font.bold: true
                                font.family: "monospace"
                                font.pixelSize: 10
                            }
                        }
                    }
                }
                }

                Repeater {
                    model: root.recordRows(tblock.p)
                    delegate: Row {
                        id: trow
                        required property int index

                        Repeater {
                            model: tblock.info.cols
                            delegate: TextField {
                                required property int index
                                width: root.cellWidth(tblock.info, index)
                                height: 28
                                text: root.cellText(tblock.p, trow.index, index)
                                placeholderText: index === 0 && tblock.info.kind === "dict"
                                                 ? "键" : "值"
                                font.family: "monospace"
                                font.pixelSize: 11
                                onTextEdited: root.setCellText(tblock.p, trow.index, index, text)
                            }
                        }
                        D.ToolButton {
                            text: "✕"
                            implicitWidth: 26
                            implicitHeight: 26
                            onClicked: root.removeRecordRow(tblock.p, trow.index)
                            ToolTip.visible: hovered
                            ToolTip.text: "删掉这一行"
                        }
                    }
                }

                Label {
                    visible: root.recordRows(tblock.p) === 0
                    text: "还没有条目，点「＋ 加一行」"
                    color: theme.textFaint
                    font.pixelSize: 10
                }
            }
        }
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
                        implicitHeight: 28
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
                            implicitHeight: 28
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
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            visible: root.result !== null && root.result.ok
            text: root.result
                  ? ("✓  返回签名: " + (root.result.signature === "" ? "（空）"
                                                                   : root.result.signature))
                  : ""
            color: theme.ok
            font.family: "monospace"
            font.pixelSize: 11
        }
        D.ToolButton {
            visible: root.result !== null && root.result.ok
            text: "复制返回"
            implicitWidth: 70
            implicitHeight: 26
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
