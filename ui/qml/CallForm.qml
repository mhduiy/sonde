import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "kinds.js" as K

/// 签名驱动的参数编辑器 + 调用。
///
/// 表单完全由 D-Bus 签名生成（Rust 的 type_tree），不用手写 GVariant 文本。
/// 值树在 JS 里递归拍平成行，界面用非递归列表渲染。
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

    spacing: 8

    function clone(x) {
        // 必须 JSON 往返：`property var` 持有 QVariantList 时元素是临时副本，
        // 直接改 nodes[0].text 写不回去。
        return JSON.parse(JSON.stringify(x))
    }

    function reset() {
        root.nodes = clone(bridge.typeTree(root.sig))
        root.result = null
        root.resultRows = []
        root.busy = false
        rebuild()
    }

    function isComposite(kind) {
        return kind === "array" || kind === "dict" || kind === "struct" || kind === "variant"
    }

    function rebuild() {
        var out = []
        for (var i = 0; i < root.nodes.length; ++i)
            walk(root.nodes[i], 0, "[" + i + "]", null, -1, out)
        root.rows = out
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

    /// 自检用：给第一个空的字符串参数填个值（便于让调用真的成功）
    function fillFirstString(v) {
        for (var i = 0; i < root.nodes.length; ++i) {
            var n = root.nodes[i]
            if (n && n.kind === "str" && (n.text === undefined || n.text === "")) {
                n.text = v
                rebuild()
                return true
            }
        }
        return false
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

    Label {
        text: "参数" + (root.sig === "" ? "（无）" : "（" + root.sig + "）")
        color: theme.textDim
        font.bold: true
        font.pixelSize: 11
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
                              : Math.min(280, root.rows.length * 32 + 8)
        clip: true
        visible: root.rows.length > 0

        ColumnLayout {
            width: parent.width
            spacing: 3

            Repeater {
                model: root.rows
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 6

                    Item {
                        Layout.preferredWidth: modelData.depth * 14
                        Layout.fillHeight: true
                    }

                    Label {
                        Layout.preferredWidth: 74
                        text: modelData.label
                        color: theme.textFaint
                        font.family: "monospace"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    TextField {
                        Layout.fillWidth: true
                        visible: !modelData.composite && modelData.node.kind !== "variant"
                        text: modelData.node.text !== undefined ? ("" + modelData.node.text) : ""
                        placeholderText: modelData.kind
                        font.family: "monospace"
                        font.pixelSize: 12
                        onTextEdited: modelData.node.text = text
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: modelData.node.kind === "variant"
                        TextField {
                            Layout.preferredWidth: 64
                            text: modelData.node.text || "s"
                            placeholderText: "内层签名"
                            font.family: "monospace"
                            font.pixelSize: 12
                            onEditingFinished: modelData.node.text = text
                        }
                        Button {
                            text: "应用"
                            implicitHeight: 26
                            onClicked: {
                                modelData.node.text = modelData.node.text || "s"
                                root.applyVariant(modelData.node)
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: root.summaryOf(modelData.node)
                            color: theme.accent
                            font.family: "monospace"
                            font.pixelSize: 11
                        }
                    }

                    Label {
                        visible: modelData.composite && modelData.node.kind !== "variant"
                        Layout.preferredWidth: 150
                        text: root.summaryOf(modelData.node)
                        color: theme.accent
                        font.family: "monospace"
                        font.pixelSize: 11
                    }

                    Label {
                        Layout.preferredWidth: 36
                        text: modelData.kind
                        color: theme.textFaint
                        font.family: "monospace"
                        font.pixelSize: 10
                    }

                    Button {
                        visible: modelData.node.kind === "array" || modelData.node.kind === "dict"
                        text: "＋"
                        implicitWidth: 30
                        implicitHeight: 26
                        onClicked: root.addChild(modelData.node)
                    }
                    Button {
                        visible: modelData.removable
                        text: "－"
                        implicitWidth: 30
                        implicitHeight: 26
                        onClicked: root.removeChild(modelData)
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- 发送 / 结果
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Button {
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

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3
        visible: root.resultRows.length > 0

        Repeater {
            model: root.resultRows
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 8

                Item {
                    Layout.preferredWidth: modelData.depth * 14
                    Layout.fillHeight: true
                }
                Label {
                    Layout.preferredWidth: 92
                    text: modelData.label
                    color: theme.textFaint
                    font.family: "monospace"
                    font.pixelSize: 11
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
